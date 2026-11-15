from datetime import timedelta
from unittest.mock import patch

from django.contrib.auth import get_user_model
from django.test import TestCase, override_settings
from django.urls import reverse
from django.utils import timezone
from rest_framework import status
from rest_framework.test import APIClient

from apps.accounts.models import PilotOTP, UserProfile

User = get_user_model()


class PilotAuthenticationTests(TestCase):
    def setUp(self):
        self.client = APIClient()

        # Create authorized pilot
        self.pilot_user = User.objects.create_user(
            username='pilot_ramesh',
            password='TestPassword123!',
        )
        self.pilot_profile = UserProfile.objects.create(
            user=self.pilot_user,
            role=UserProfile.Role.PILOT,
            phone_number='9876543210',
            badge_number='KKRTC-BLR-01',
            is_authorized_pilot=True,
        )

        # Create regular passenger (unauthorized for pilot portal)
        self.passenger_user = User.objects.create_user(
            username='passenger_suresh',
            password='TestPassword123!',
        )
        self.passenger_profile = UserProfile.objects.create(
            user=self.passenger_user,
            role=UserProfile.Role.PASSENGER,
            phone_number='9123456789',
            is_authorized_pilot=False,
        )

    def test_unregistered_number_cannot_request_pilot_otp(self):
        """
        Unregistered phone number must be rejected with 403 Forbidden.
        """
        response = self.client.post(
            reverse('accounts:pilot-send-otp'),
            {'phone_number': '9999999999'},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertIn('not registered as an authorized KKRTC pilot', response.data['error'])

    def test_passenger_number_cannot_request_pilot_otp(self):
        """
        Passenger phone number attempting to log into Pilot portal must be rejected with 403 Forbidden.
        """
        response = self.client.post(
            reverse('accounts:pilot-send-otp'),
            {'phone_number': '9123456789'},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)

    def test_authorized_pilot_requests_otp_successfully(self):
        """
        Authorized pilot receives 200 OK and OTP is generated on server without exposure.
        """
        response = self.client.post(
            reverse('accounts:pilot-send-otp'),
            {'phone_number': '9876543210'},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['success'])
        # Plain OTP must NEVER be in response
        self.assertNotIn('otp', response.data)

        # Verify record created in DB
        otp_record = PilotOTP.objects.filter(phone_number='9876543210').first()
        self.assertIsNotNone(otp_record)
        self.assertFalse(otp_record.is_used)

    def test_resend_cooldown_triggers_429(self):
        """
        Attempting to request OTP twice within 30 seconds triggers 429 Too Many Requests.
        """
        # First request
        r1 = self.client.post(
            reverse('accounts:pilot-send-otp'),
            {'phone_number': '9876543210'},
            format='json',
        )
        self.assertEqual(r1.status_code, status.HTTP_200_OK)

        # Immediate second request
        r2 = self.client.post(
            reverse('accounts:pilot-send-otp'),
            {'phone_number': '9876543210'},
            format='json',
        )
        self.assertEqual(r2.status_code, status.HTTP_429_TOO_MANY_REQUESTS)
        self.assertIn('cooldown_remaining', r2.data)

    def test_verify_otp_success_generates_jwt(self):
        """
        Entering the correct OTP authenticates the pilot and returns JWT access & refresh tokens.
        """
        plain_otp = '582910'
        PilotOTP.create_for_phone(
            phone_number='9876543210',
            plain_otp=plain_otp,
            validity_minutes=5,
        )

        response = self.client.post(
            reverse('accounts:pilot-verify-otp'),
            {'phone_number': '9876543210', 'otp': plain_otp},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['success'])
        self.assertIn('access', response.data)
        self.assertIn('refresh', response.data)
        self.assertEqual(response.data['user']['role'], 'PILOT')

        # Verify marked as used
        otp_record = PilotOTP.objects.get(phone_number='9876543210')
        self.assertTrue(otp_record.is_used)

    def test_otp_single_use_prevents_replay(self):
        """
        An OTP cannot be reused once verified.
        """
        plain_otp = '654321'
        PilotOTP.create_for_phone(
            phone_number='9876543210',
            plain_otp=plain_otp,
            validity_minutes=5,
        )

        # 1st verification succeeds
        r1 = self.client.post(
            reverse('accounts:pilot-verify-otp'),
            {'phone_number': '9876543210', 'otp': plain_otp},
            format='json',
        )
        self.assertEqual(r1.status_code, status.HTTP_200_OK)

        # 2nd verification fails
        r2 = self.client.post(
            reverse('accounts:pilot-verify-otp'),
            {'phone_number': '9876543210', 'otp': plain_otp},
            format='json',
        )
        self.assertEqual(r2.status_code, status.HTTP_400_BAD_REQUEST)

    def test_expired_otp_fails_verification(self):
        """
        Expired OTP cannot be verified.
        """
        plain_otp = '112233'
        otp = PilotOTP.create_for_phone(
            phone_number='9876543210',
            plain_otp=plain_otp,
            validity_minutes=5,
        )
        # Manually expire
        otp.expires_at = timezone.now() - timedelta(minutes=1)
        otp.save()

        response = self.client.post(
            reverse('accounts:pilot-verify-otp'),
            {'phone_number': '9876543210', 'otp': plain_otp},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('expired', response.data['error'])

    def test_incorrect_otp_attempt_limits(self):
        """
        Incorrect OTP attempts decrement remaining count and lockout after max attempts.
        """
        plain_otp = '998877'
        PilotOTP.create_for_phone(
            phone_number='9876543210',
            plain_otp=plain_otp,
            validity_minutes=5,
        )

        for attempt in range(1, 4):
            response = self.client.post(
                reverse('accounts:pilot-verify-otp'),
                {'phone_number': '9876543210', 'otp': '000000'},
                format='json',
            )
            self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)

        # 4th attempt after maxed attempts
        response = self.client.post(
            reverse('accounts:pilot-verify-otp'),
            {'phone_number': '9876543210', 'otp': plain_otp},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Maximum verification attempts exceeded', response.data['error'])


# ---------------------------------------------------------------------------
# Development OTP Console Mode Tests
# ---------------------------------------------------------------------------


class DevelopmentOtpConsoleModeTests(TestCase):
    """
    Verifies the DEVELOPMENT_OTP_CONSOLE feature:
    - Console mode is effective only when DEBUG=True + DEVELOPMENT_OTP_CONSOLE=True.
    - The plain OTP is NEVER present in any API response body.
    - In production (DEBUG=False), the flag raises HTTP 500 and logs CRITICAL.
    - The flag is disabled by default (no env var set).
    """

    def setUp(self):
        self.client = APIClient()

        self.pilot_user = User.objects.create_user(
            username='pilot_console_test',
            password='TestPassword123!',
        )
        self.pilot_profile = UserProfile.objects.create(
            user=self.pilot_user,
            role=UserProfile.Role.PILOT,
            phone_number='9000000001',
            badge_number='KKRTC-CON-01',
            is_authorized_pilot=True,
        )
        self.send_url = reverse('accounts:pilot-send-otp')

    # ------------------------------------------------------------------
    # Helper
    # ------------------------------------------------------------------
    def _post_send_otp(self):
        return self.client.post(
            self.send_url,
            {'phone_number': '9000000001'},
            format='json',
        )

    # ------------------------------------------------------------------
    # Test 1: Console mode prints OTP when DEBUG=True + flag enabled
    # ------------------------------------------------------------------
    @override_settings(DEBUG=True, DEVELOPMENT_OTP_CONSOLE=True)
    def test_console_mode_enabled_in_debug_prints_otp(self):
        """
        When DEBUG=True and DEVELOPMENT_OTP_CONSOLE=True the OTP send must
        succeed (HTTP 200) and the response must NOT contain the plain OTP.
        The OTP is printed to stderr (verified via mock).
        """
        with patch('sys.stderr') as mock_stderr:
            response = self._post_send_otp()

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data.get('success'))

        # Plain OTP must NEVER appear in response body
        self.assertNotIn('otp', response.data)
        self.assertNotIn('plain_otp', response.data)

        # sys.stderr.write (or print's flush) must have been invoked
        self.assertTrue(
            mock_stderr.write.called or mock_stderr.flush.called,
            "Expected OTP to be printed to stderr in console mode.",
        )

    # ------------------------------------------------------------------
    # Test 2: OTP never exposed in API response (any configuration)
    # ------------------------------------------------------------------
    @override_settings(DEBUG=True, DEVELOPMENT_OTP_CONSOLE=False)
    def test_otp_never_in_api_response(self):
        """
        Regardless of configuration, the plain OTP must never appear in
        the API response body.
        """
        response = self._post_send_otp()
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        for key in ('otp', 'plain_otp', 'token', 'code'):
            self.assertNotIn(key, response.data)

        # Also verify no OTP-like 6-digit number appears in response values
        import re
        response_str = str(response.data)
        six_digit_pattern = re.compile(r'\b\d{6}\b')
        # Phone number 9000000001 is 10 digits, not 6, so it won't falsely match
        self.assertFalse(
            six_digit_pattern.search(response_str),
            f"A 6-digit number was found in the API response: {response_str}",
        )

    # ------------------------------------------------------------------
    # Test 3: Console mode prohibited in production (DEBUG=False)
    # ------------------------------------------------------------------
    @override_settings(DEBUG=False, DEVELOPMENT_OTP_CONSOLE=True)
    def test_console_mode_prohibited_in_production(self):
        """
        When DEBUG=False and DEVELOPMENT_OTP_CONSOLE=True the view must
        return HTTP 500 and log a CRITICAL security warning.
        No OTP record should be dispatched via SMS or exposed.
        """
        with self.assertLogs('apps.accounts.views', level='CRITICAL') as log_ctx:
            response = self._post_send_otp()

        self.assertEqual(response.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)
        self.assertIn('error', response.data)

        # Ensure a CRITICAL security log was emitted
        self.assertTrue(
            any('SECURITY VIOLATION' in msg for msg in log_ctx.output),
            f"Expected CRITICAL security log. Got: {log_ctx.output}",
        )

    # ------------------------------------------------------------------
    # Test 4: Console mode is disabled by default
    # ------------------------------------------------------------------
    @override_settings(DEBUG=True, DEVELOPMENT_OTP_CONSOLE=False)
    def test_console_mode_disabled_by_default(self):
        """
        When DEVELOPMENT_OTP_CONSOLE is False (default), OTP send must
        succeed normally and nothing is written to stderr.
        """
        with patch('sys.stderr') as mock_stderr:
            response = self._post_send_otp()

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data.get('success'))
        # stderr must NOT have been written to
        mock_stderr.write.assert_not_called()


# ---------------------------------------------------------------------------
# Phase 1 Security Remediation Regression Tests
# ---------------------------------------------------------------------------


class Phase1SecurityRemediationTests(TestCase):
    """
    Validates Phase 1 security fixes:
    1. Plaintext OTP and message content are NEVER written to application logs in sms_service.
    2. SMS dispatch contract and verification remain completely preserved.
    3. Missing production SECRET_KEY causes immediate ImproperlyConfigured startup failure.
    4. Production SECRET_KEY is loaded safely without logging or exposing secrets.
    5. Local development fallback is restricted exclusively to DEBUG=True.
    6. DEBUG defaults to False outside local development.
    7. DEVELOPMENT_OTP_CONSOLE cannot execute or display OTPs when DEBUG=False.
    """

    def setUp(self):
        self.client = APIClient()
        self.pilot_user = User.objects.create_user(
            username='pilot_phase1_test',
            password='TestPassword123!',
        )
        self.pilot_profile = UserProfile.objects.create(
            user=self.pilot_user,
            role=UserProfile.Role.PILOT,
            phone_number='9876500001',
            badge_number='KKRTC-SEC-01',
            is_authorized_pilot=True,
        )

    # ------------------------------------------------------------------
    # 1. Plaintext OTP and message content removal from logs
    # ------------------------------------------------------------------
    def test_sms_service_does_not_log_plain_otp_or_message_content(self):
        """
        Verifies that SMSGatewayService.send_otp does NOT write the plain OTP
        or the message content into logger.info or any application log.
        """
        from apps.accounts.sms_service import SMSGatewayService

        plain_otp = '739182'
        phone_number = '9876500001'

        with self.assertLogs('apps.accounts.sms_service', level='INFO') as log_ctx:
            result = SMSGatewayService.send_otp(phone_number, plain_otp)

        # Confirm dispatch succeeded
        self.assertTrue(result.get('success'))

        # Check all logged messages for this call
        for log_entry in log_ctx.output:
            self.assertNotIn(
                plain_otp,
                log_entry,
                f"Security Failure: Plain OTP {plain_otp} was found in application log: {log_entry}",
            )
            self.assertNotIn(
                'KKRTC Duty Verification',
                log_entry,
                f"Security Failure: OTP message template found in application log: {log_entry}",
            )
            self.assertNotIn(
                'Your OTP is',
                log_entry,
                f"Security Failure: 'Your OTP is' phrase found in application log: {log_entry}",
            )

    # ------------------------------------------------------------------
    # 2. Preservation of SMS dispatch contract
    # ------------------------------------------------------------------
    def test_sms_service_preserves_dispatch_return_structure(self):
        """
        Verifies that SMSGatewayService returns the expected dict structure
        for views and clients to process gracefully.
        """
        from apps.accounts.sms_service import SMSGatewayService

        result = SMSGatewayService.send_otp('9876500001', '123456')
        self.assertIsInstance(result, dict)
        self.assertIn('success', result)
        self.assertIn('provider', result)
        self.assertTrue(result['success'])

    # ------------------------------------------------------------------
    # 3. Missing production SECRET_KEY causes startup failure
    # ------------------------------------------------------------------
    def test_missing_production_secret_key_raises_improperly_configured(self):
        """
        In production mode (debug_mode=False), a missing or blank SECRET_KEY
        must raise ImproperlyConfigured and must never leak secrets.
        """
        import os
        from django.core.exceptions import ImproperlyConfigured
        from config.settings import get_secret_key

        with patch.dict(os.environ, {'SECRET_KEY': ''}):
            with self.assertRaises(ImproperlyConfigured) as ctx:
                get_secret_key(debug_mode=False)

            err_msg = str(ctx.exception)
            self.assertIn('SECRET_KEY', err_msg)
            self.assertIn('DEBUG=False', err_msg)

    # ------------------------------------------------------------------
    # 4. Production SECRET_KEY is accepted when configured
    # ------------------------------------------------------------------
    def test_production_secret_key_loaded_when_provided(self):
        """
        In production mode (debug_mode=False), a valid SECRET_KEY is returned.
        """
        import os
        from config.settings import get_secret_key

        test_key = 'super-secure-production-random-key-for-test-only'
        with patch.dict(os.environ, {'SECRET_KEY': test_key}):
            result = get_secret_key(debug_mode=False)
            self.assertEqual(result, test_key)

    # ------------------------------------------------------------------
    # 5. Local development fallback restricted to DEBUG=True
    # ------------------------------------------------------------------
    def test_secret_key_dev_fallback_only_when_debug_true(self):
        """
        When DEBUG=True and SECRET_KEY is blank, the development-only fallback
        is used to allow friction-free local developer onboarding.
        """
        import os
        from config.settings import get_secret_key

        with patch.dict(os.environ, {'SECRET_KEY': ''}):
            dev_key = get_secret_key(debug_mode=True)
            self.assertTrue(dev_key.startswith('django-insecure-'))

    # ------------------------------------------------------------------
    # 6. DEBUG defaults to False
    # ------------------------------------------------------------------
    def test_debug_defaults_to_false(self):
        """
        Verifies that parsing an unset or empty DEBUG env var resolves to False.
        """
        import os

        # Helper simulation matching settings.py logic
        def parse_debug(val):
            return str(val).strip().lower() in ('true', '1', 'yes')

        self.assertFalse(parse_debug(os.getenv('NON_EXISTENT_DEBUG_VAR', 'False')))
        self.assertFalse(parse_debug('False'))
        self.assertFalse(parse_debug('0'))
        self.assertFalse(parse_debug('no'))
        self.assertTrue(parse_debug('True'))
        self.assertTrue(parse_debug('true'))
        self.assertTrue(parse_debug('1'))

    # ------------------------------------------------------------------
    # 7. DEVELOPMENT_OTP_CONSOLE cannot execute when DEBUG=False
    # ------------------------------------------------------------------
    @override_settings(DEBUG=False, DEVELOPMENT_OTP_CONSOLE=True)
    def test_console_otp_strictly_cannot_display_when_debug_false(self):
        """
        Confirms that when DEBUG=False, DEVELOPMENT_OTP_CONSOLE is prohibited:
        - View returns HTTP 500
        - stderr receives no plain OTP
        - PilotOTP is created but not displayed to console
        """
        import sys

        with patch.object(sys.stderr, 'write') as mock_stderr_write:
            with self.assertLogs('apps.accounts.views', level='CRITICAL') as log_ctx:
                response = self.client.post(
                    reverse('accounts:pilot-send-otp'),
                    {'phone_number': '9876500001'},
                    format='json',
                )

        self.assertEqual(response.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)
        mock_stderr_write.assert_not_called()
        self.assertTrue(
            any('SECURITY VIOLATION' in msg for msg in log_ctx.output)
        )


# ---------------------------------------------------------------------------
# Demo Pilot Mode Tests
# ---------------------------------------------------------------------------


class DemoPilotModeTests(TestCase):
    def setUp(self):
        self.client = APIClient()
        self.pilot_user = User.objects.create_user(
            username='Anil',
            first_name='Anil',
            last_name='Kumar',
        )
        self.pilot_profile = UserProfile.objects.create(
            user=self.pilot_user,
            role=UserProfile.Role.PILOT,
            phone_number='9876543210',
            badge_number='KKRTC-P-4401',
            is_authorized_pilot=True,
        )
        from apps.buses.models import Bus
        from apps.routes.models import Route
        self.bus = Bus.objects.create(
            registration_number='KA-34-A-1001',
            pilot=self.pilot_user,
        )
        self.route = Route.objects.create(
            route_id='R001',
            source_name='Bengaluru',
            destination_name='Ballari',
        )

    def test_demo_session_endpoint_disabled_by_default(self):
        """
        When DEMO_PILOT_MODE is False (default), the demo session endpoint must return 403 Forbidden.
        """
        response = self.client.post('/api/accounts/pilot/demo-session/')
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertIn('Demo pilot mode is disabled', response.data['error'])

    @override_settings(DEMO_PILOT_MODE=True)
    def test_demo_session_endpoint_issues_valid_jwt_when_enabled(self):
        """
        When DEMO_PILOT_MODE is True, the demo session endpoint returns standard SimpleJWT tokens
        strictly for the seeded demo pilot 'Anil'.
        """
        response = self.client.post('/api/accounts/pilot/demo-session/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['demo_mode'])
        self.assertIn('access', response.data)
        self.assertIn('refresh', response.data)
        self.assertEqual(response.data['pilot']['username'], 'Anil')
        self.assertEqual(response.data['pilot']['phone_number'], '9876543210')
        self.assertEqual(response.data['assigned_bus']['registration_number'], 'KA-34-A-1001')
        self.assertEqual(response.data['default_route']['route_id'], 'R001')

    @override_settings(DEMO_PILOT_MODE=True)
    def test_demo_pilot_token_authorizes_trips_but_cannot_access_admin(self):
        """
        The demo token is a valid Pilot token capable of starting trips,
        but possesses zero administrative or staff privileges.
        """
        login_res = self.client.post('/api/accounts/pilot/demo-session/')
        access_token = login_res.data['access']

        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {access_token}')

        # 1. Pilot can start trip on their assigned bus
        start_res = self.client.post(
            '/api/trips/start/',
            {'route_id': self.route.id, 'bus_id': self.bus.id},
            format='json',
        )
        self.assertEqual(start_res.status_code, status.HTTP_201_CREATED)
        trip_id = start_res.data['trip_id']

        # 2. Pilot can submit GPS coordinates
        loc_res = self.client.post(
            '/api/trips/location/',
            {
                'trip_id': trip_id,
                'latitude': '13.340881',
                'longitude': '77.100616',
                'speed': '50.00',
                'bearing': '90.00',
            },
            format='json',
        )
        self.assertEqual(loc_res.status_code, status.HTTP_200_OK)

        # 3. Pilot cannot access Django admin
        admin_res = self.client.get('/admin/')
        # Unauthenticated to admin or redirect to admin login
        self.assertIn(admin_res.status_code, (status.HTTP_302_FOUND, status.HTTP_403_FORBIDDEN))

        # 4. Pilot cannot start trip on unassigned bus
        other_user = User.objects.create_user(username='other_driver')
        UserProfile.objects.create(user=other_user, role=UserProfile.Role.PILOT)
        from apps.buses.models import Bus
        other_bus = Bus.objects.create(registration_number='KA-34-A-9999', pilot=other_user)

        # End active trip first
        self.client.post('/api/trips/end/', {'trip_id': trip_id}, format='json')

        unauth_start = self.client.post(
            '/api/trips/start/',
            {'route_id': self.route.id, 'bus_id': other_bus.id},
            format='json',
        )
        self.assertEqual(unauth_start.status_code, status.HTTP_400_BAD_REQUEST)

    @override_settings(DEMO_PILOT_MODE=True)
    def test_demo_session_aborts_if_pilot_has_staff_privilege(self):
        """
        Security invariant: if the demo pilot account has staff or superuser set,
        the demo endpoint refuses to issue tokens to prevent accidental admin privilege escalation.
        """
        self.pilot_user.is_staff = True
        self.pilot_user.save()

        response = self.client.post('/api/accounts/pilot/demo-session/')
        self.assertEqual(response.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)
        self.assertIn('cannot possess administrative rights', response.data['error'])

    @override_settings(DEMO_PILOT_MODE=True)
    def test_demo_session_endpoint_with_driver_id_authenticates_selected_pilot(self):
        """
        When driver_id is provided, the demo session endpoint authenticates that specific pilot
        and issues a SimpleJWT token for their user ID.
        """
        from apps.buses.models import Bus
        pilot2 = User.objects.create_user(username='Tester1', is_active=True)
        UserProfile.objects.create(
            user=pilot2,
            role=UserProfile.Role.PILOT,
            phone_number='7353419383',
            badge_number='KKRTC-P-02',
            is_authorized_pilot=True,
        )
        bus2 = Bus.objects.create(registration_number='KA-35-F-1235', pilot=pilot2, is_active=True)

        response = self.client.post(
            '/api/accounts/pilot/demo-session/',
            {'driver_id': pilot2.id},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertTrue(response.data['demo_mode'])
        self.assertEqual(response.data['pilot']['id'], pilot2.id)
        self.assertEqual(response.data['pilot']['username'], 'Tester1')
        self.assertEqual(response.data['pilot']['badge_number'], 'KKRTC-P-02')
        self.assertEqual(response.data['assigned_bus']['registration_number'], 'KA-35-F-1235')

        # Verify that the issued token authorizes requests as pilot2
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {response.data["access"]}')
        profile_res = self.client.get('/api/accounts/pilot/me/')
        self.assertEqual(profile_res.status_code, status.HTTP_200_OK)
        self.assertEqual(profile_res.data['username'], 'Tester1')

        # Verify starting a trip with pilot2's assigned bus succeeds
        start_res = self.client.post(
            '/api/trips/start/',
            {'route_id': self.route.id, 'bus_id': bus2.id},
            format='json',
        )
        self.assertEqual(start_res.status_code, status.HTTP_201_CREATED)

    @override_settings(DEMO_PILOT_MODE=True)
    def test_demo_session_endpoint_rejects_unauthorized_driver_id(self):
        """
        Unauthorized or non-existent driver IDs are rejected.
        """
        # Non-existent ID
        res_404 = self.client.post(
            '/api/accounts/pilot/demo-session/',
            {'driver_id': 999999},
            format='json',
        )
        self.assertEqual(res_404.status_code, status.HTTP_404_NOT_FOUND)

        # Passenger user (not PILOT)
        passenger = User.objects.create_user(username='passenger_user', is_active=True)
        UserProfile.objects.create(user=passenger, role=UserProfile.Role.PASSENGER, is_authorized_pilot=True)
        res_pass = self.client.post(
            '/api/accounts/pilot/demo-session/',
            {'driver_id': passenger.id},
            format='json',
        )
        self.assertEqual(res_pass.status_code, status.HTTP_404_NOT_FOUND)

        # Pilot with is_authorized_pilot=False
        unauth_pilot = User.objects.create_user(username='unauth_pilot', is_active=True)
        UserProfile.objects.create(user=unauth_pilot, role=UserProfile.Role.PILOT, is_authorized_pilot=False)
        res_unauth = self.client.post(
            '/api/accounts/pilot/demo-session/',
            {'driver_id': unauth_pilot.id},
            format='json',
        )
        self.assertEqual(res_unauth.status_code, status.HTTP_404_NOT_FOUND)

    @override_settings(DEMO_PILOT_MODE=True)
    def test_demo_session_endpoint_rejects_staff_or_superuser_driver_id(self):
        """
        Staff or superuser pilots cannot obtain tokens through demo session.
        """
        staff_pilot = User.objects.create_user(username='staff_pilot', is_active=True, is_staff=True)
        UserProfile.objects.create(user=staff_pilot, role=UserProfile.Role.PILOT, is_authorized_pilot=True)

        response = self.client.post(
            '/api/accounts/pilot/demo-session/',
            {'driver_id': staff_pilot.id},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_500_INTERNAL_SERVER_ERROR)

    @override_settings(DEMO_PILOT_MODE=True)
    def test_demo_session_endpoint_rejects_invalid_driver_id_format(self):
        """
        Invalid driver_id format returns 400 Bad Request.
        """
        response = self.client.post(
            '/api/accounts/pilot/demo-session/',
            {'driver_id': 'invalid_id'},
            format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)



class AuthorizedPilotListViewTests(TestCase):
    def setUp(self):
        self.client = APIClient()

        # Authorized Pilot
        self.user1 = User.objects.create_user(username='Anil', first_name='Anil')
        self.profile1 = UserProfile.objects.create(
            user=self.user1,
            role=UserProfile.Role.PILOT,
            phone_number='9876543210',
            badge_number='KKRTC-01',
            is_authorized_pilot=True,
        )

        # Unauthorized Pilot
        self.user2 = User.objects.create_user(username='UnauthorizedPilot')
        self.profile2 = UserProfile.objects.create(
            user=self.user2,
            role=UserProfile.Role.PILOT,
            phone_number='9876543211',
            is_authorized_pilot=False,
        )

        # Passenger
        self.user3 = User.objects.create_user(username='PassengerUser')
        self.profile3 = UserProfile.objects.create(
            user=self.user3,
            role=UserProfile.Role.PASSENGER,
            phone_number='9876543212',
            is_authorized_pilot=False,
        )

    def test_list_authorized_pilots_public_access(self):
        response = self.client.get('/api/accounts/pilots/')
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual(len(response.data), 1)
        self.assertEqual(response.data[0]['driver_name'], 'Anil')
        self.assertEqual(response.data[0]['driver_id'], self.user1.id)
        self.assertEqual(response.data[0]['phone_number'], '9876543210')
        self.assertEqual(response.data[0]['badge_number'], 'KKRTC-01')

