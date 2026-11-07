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
