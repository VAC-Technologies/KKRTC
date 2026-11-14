import logging
import secrets
import sys
from datetime import timedelta

from django.conf import settings as django_settings
from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework import permissions, status
from rest_framework.response import Response
from rest_framework.throttling import ScopedRateThrottle
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken

from apps.accounts.models import PilotOTP, UserProfile
from apps.accounts.serializers import (
    SendOtpSerializer,
    UserProfileSerializer,
    VerifyOtpSerializer,
)
from apps.accounts.sms_service import SMSGatewayService
from apps.buses.models import Bus
from apps.routes.models import Route

logger = logging.getLogger(__name__)

User = get_user_model()


class PilotSendOtpView(APIView):
    """
    Generates and dispatches a cryptographically secure 6-digit OTP to registered pilots.
    Rejects unauthorized phone numbers with HTTP 403.
    Enforces a 30-second resend cooldown.
    """
    permission_classes = (permissions.AllowAny,)

    def post(self, request):
        serializer = SendOtpSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        phone_number = serializer.validated_data['phone_number']

        # 1. Authorize Pilot
        # Check whether this phone number belongs to an active, authorized KKRTC pilot
        profile = UserProfile.objects.select_related('user').filter(
            phone_number=phone_number,
            role=UserProfile.Role.PILOT,
            is_authorized_pilot=True,
            user__is_active=True,
        ).first()

        if not profile:
            # Check if user exists by username or staff for development/demo ease
            # but reject arbitrary public phone numbers
            return Response(
                {
                    'error': (
                        'This mobile number is not registered as an authorized KKRTC pilot. '
                        'Please verify with your depot superintendent.'
                    )
                },
                status=status.HTTP_403_FORBIDDEN,
            )

        # 2. Check Resend Cooldown (30 seconds)
        recent_otp = PilotOTP.objects.filter(
            phone_number=phone_number,
            created_at__gte=timezone.now() - timedelta(seconds=30),
        ).first()

        if recent_otp:
            elapsed = (timezone.now() - recent_otp.created_at).total_seconds()
            remaining = max(1, int(30 - elapsed))
            return Response(
                {
                    'error': f'Please wait {remaining} seconds before requesting another OTP.',
                    'cooldown_remaining': remaining,
                },
                status=status.HTTP_429_TOO_MANY_REQUESTS,
            )

        # 3. Cryptographically Secure Random OTP Generation (6 digits: 100000 - 999999)
        # Generated ONLY on server, never exposed in client payload
        plain_otp = f'{secrets.randbelow(900000) + 100000}'

        # 4. Record OTP Hash in Database
        PilotOTP.create_for_phone(
            phone_number=phone_number,
            plain_otp=plain_otp,
            validity_minutes=5,
        )

        # 5. Development-only: OTP Console Display
        # Prints the plain OTP to the Django management terminal ONLY when both
        # DEBUG=True and DEVELOPMENT_OTP_CONSOLE=True.  The plain OTP is NEVER
        # included in API responses, Django logs, or the database.
        dev_console = getattr(django_settings, 'DEVELOPMENT_OTP_CONSOLE', False)
        if django_settings.DEBUG and dev_console:
            print(
                f"\n{'=' * 60}\n"
                f"[KKRTC DEV OTP]  Phone : {phone_number}\n"
                f"[KKRTC DEV OTP]  OTP   : {plain_otp}\n"
                f"[KKRTC DEV OTP]  Valid for 5 minutes.\n"
                f"[KKRTC DEV OTP]  ⚠  NEVER enable in production.\n"
                f"{'=' * 60}\n",
                file=sys.stderr,
                flush=True,
            )
        elif not django_settings.DEBUG and dev_console:
            # Prohibit in production: log a critical security warning and abort.
            logger.critical(
                "SECURITY VIOLATION: DEVELOPMENT_OTP_CONSOLE=True while DEBUG=False. "
                "This setting is prohibited outside DEBUG mode. OTP send rejected."
            )
            return Response(
                {'error': 'Server configuration error. Contact the system administrator.'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        # 6. Dispatch via Real SMS Gateway
        sms_result = SMSGatewayService.send_otp(phone_number, plain_otp)

        return Response(
            {
                'success': True,
                'message': 'OTP sent successfully to registered pilot mobile number.',
                'phone_number': phone_number,
                'cooldown_seconds': 30,
                'gateway': sms_result.get('provider'),
                'pending_config': sms_result.get('pending_config', False),
            },
            status=status.HTTP_200_OK,
        )


class PilotVerifyOtpView(APIView):
    """
    Verifies the server-generated OTP, checks expiration and attempt limits,
    and returns JWT tokens upon success.
    """
    permission_classes = (permissions.AllowAny,)

    def post(self, request):
        serializer = VerifyOtpSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        phone_number = serializer.validated_data['phone_number']
        plain_otp = serializer.validated_data['otp']

        # Find latest unexpired, unused OTP record
        otp_record = PilotOTP.objects.filter(
            phone_number=phone_number,
            is_used=False,
        ).order_by('-created_at').first()

        if not otp_record:
            return Response(
                {
                    'error': 'No active OTP found for this number. Please request a new OTP.'
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Verify against hashed OTP and increment attempts
        is_valid, msg = otp_record.check_otp(plain_otp)
        if not is_valid:
            return Response({'error': msg}, status=status.HTTP_400_BAD_REQUEST)

        # Retrieve pilot profile and user
        profile = UserProfile.objects.select_related('user').filter(
            phone_number=phone_number,
            role=UserProfile.Role.PILOT,
            is_authorized_pilot=True,
            user__is_active=True,
        ).first()

        if not profile:
            return Response(
                {'error': 'Pilot account is not active or unauthorized.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        # Generate JWT Tokens
        refresh = RefreshToken.for_user(profile.user)

        return Response(
            {
                'success': True,
                'message': 'Authentication successful.',
                'access': str(refresh.access_token),
                'refresh': str(refresh),
                'user': {
                    'id': profile.user.id,
                    'username': profile.user.username,
                    'role': profile.role,
                    'phone_number': profile.phone_number,
                    'badge_number': profile.badge_number,
                },
            },
            status=status.HTTP_200_OK,
        )


class CurrentPilotProfileView(APIView):
    """
    Returns profile information for the authenticated pilot.
    """
    permission_classes = (permissions.IsAuthenticated,)

    def get(self, request):
        profile = getattr(request.user, 'profile', None)
        if not profile:
            return Response(
                {'error': 'User has no associated profile.'},
                status=status.HTTP_404_NOT_FOUND,
            )
        serializer = UserProfileSerializer(profile)
        return Response(serializer.data, status=status.HTTP_200_OK)


class DemoPilotSessionView(APIView):
    """
    Controlled Demo Session Endpoint for campus testing.
    Issues a restricted SimpleJWT token strictly for the seeded demo pilot 'Anil'.
    Active ONLY when DEMO_PILOT_MODE=True.
    Protected by rate limiting.
    """
    permission_classes = (permissions.AllowAny,)
    throttle_classes = (ScopedRateThrottle,)
    throttle_scope = 'demo_session'

    def post(self, request):
        if not getattr(django_settings, 'DEMO_PILOT_MODE', False):
            return Response(
                {'error': 'Demo pilot mode is disabled.'},
                status=status.HTTP_403_FORBIDDEN,
            )

        # Retrieve explicitly seeded demo pilot
        pilot_user = User.objects.select_related('profile').filter(
            username='Anil',
            profile__phone_number='9876543210',
            profile__role=UserProfile.Role.PILOT,
            profile__is_authorized_pilot=True,
            is_active=True,
        ).first()

        if not pilot_user:
            return Response(
                {'error': 'Demo pilot account is not initialized or unauthorized.'},
                status=status.HTTP_404_NOT_FOUND,
            )

        # Enforce no administrative or superuser privileges
        if pilot_user.is_staff or pilot_user.is_superuser:
            logger.error("Security alert: demo pilot user has staff/superuser flag set.")
            return Response(
                {'error': 'Configuration violation: demo pilot cannot possess administrative rights.'},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        # Fetch assigned bus and default route
        assigned_bus = Bus.objects.filter(pilot=pilot_user, is_active=True).first()
        default_route = Route.objects.filter(is_active=True).order_by('route_id').first()

        refresh = RefreshToken.for_user(pilot_user)
        refresh['demo_mode'] = True

        return Response(
            {
                'demo_mode': True,
                'message': 'Demo pilot session established.',
                'access': str(refresh.access_token),
                'refresh': str(refresh),
                'pilot': {
                    'id': pilot_user.id,
                    'username': pilot_user.username,
                    'role': pilot_user.profile.role,
                    'phone_number': pilot_user.profile.phone_number,
                    'badge_number': pilot_user.profile.badge_number,
                },
                'assigned_bus': {
                    'id': assigned_bus.id,
                    'registration_number': assigned_bus.registration_number,
                } if assigned_bus else None,
                'default_route': {
                    'id': default_route.id,
                    'route_id': default_route.route_id,
                    'source_name': default_route.source_name,
                    'destination_name': default_route.destination_name,
                } if default_route else None,
            },
            status=status.HTTP_200_OK,
        )
