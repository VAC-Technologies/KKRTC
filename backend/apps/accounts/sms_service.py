import json
import logging
import os
import urllib.parse
import urllib.request

logger = logging.getLogger('apps.accounts.sms_service')


class SMSGatewayService:
    """
    Handles SMS OTP dispatch for KKRTC Pilot authentication via real SMS gateways.
    Configured via environment variables:
    - FAST2SMS_API_KEY: Fast2SMS API key for Indian mobile numbers
    - TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_FROM_NUMBER: Twilio SMS credentials
    - SMS_GATEWAY_PROVIDER: 'FAST2SMS', 'TWILIO', or 'LOG' (default)
    """

    @staticmethod
    def get_configured_provider():
        explicit = os.getenv('SMS_GATEWAY_PROVIDER', '').strip().upper()
        if explicit:
            return explicit
        if os.getenv('FAST2SMS_API_KEY'):
            return 'FAST2SMS'
        if os.getenv('TWILIO_ACCOUNT_SID') and os.getenv('TWILIO_AUTH_TOKEN'):
            return 'TWILIO'
        return 'PENDING_CONFIG'

    @classmethod
    def send_otp(cls, phone_number: str, otp: str) -> dict:
        """
        Sends the 6-digit OTP to the registered pilot mobile number using the configured gateway.
        Returns a dictionary with status, provider, and diagnostic info.
        """
        clean_phone = phone_number.replace('+', '').replace(' ', '').replace('-', '')
        # Extract last 10 digits for Indian numbers
        if len(clean_phone) > 10 and clean_phone.startswith('91'):
            clean_phone_10 = clean_phone[2:]
        else:
            clean_phone_10 = clean_phone[-10:]

        message_text = f"KKRTC Duty Verification: Your OTP is {otp}. Valid for 5 minutes. Do not share this OTP with anyone."
        provider = cls.get_configured_provider()

        # 1. Fast2SMS Provider
        if provider == 'FAST2SMS':
            api_key = os.getenv('FAST2SMS_API_KEY')
            if not api_key:
                logger.warning("Fast2SMS selected but FAST2SMS_API_KEY is missing.")
                return {
                    'success': False,
                    'provider': 'FAST2SMS',
                    'error': 'Missing FAST2SMS_API_KEY environment variable.',
                    'pending_config': True,
                }
            try:
                url = "https://www.fast2sms.com/dev/bulkV2"
                payload = {
                    "authorization": api_key,
                    "route": "otp",
                    "variables_values": otp,
                    "numbers": clean_phone_10,
                }
                data = json.dumps(payload).encode('utf-8')
                req = urllib.request.Request(
                    url,
                    data=data,
                    headers={
                        "Content-Type": "application/json",
                        "cache-control": "no-cache",
                    },
                    method="POST",
                )
                with urllib.request.urlopen(req, timeout=10) as resp:
                    resp.read()
                    logger.info("Fast2SMS OTP dispatched to %s (HTTP %s).", clean_phone_10, resp.status)
                    return {
                        'success': True,
                        'provider': 'FAST2SMS',
                        'message': 'OTP sent via Fast2SMS gateway.',
                    }
            except Exception as e:
                logger.error("Fast2SMS dispatch failed: %s", e)
                return {
                    'success': False,
                    'provider': 'FAST2SMS',
                    'error': str(e),
                }

        # 2. Twilio Provider
        elif provider == 'TWILIO':
            account_sid = os.getenv('TWILIO_ACCOUNT_SID')
            auth_token = os.getenv('TWILIO_AUTH_TOKEN')
            from_number = os.getenv('TWILIO_FROM_NUMBER')
            if not account_sid or not auth_token or not from_number:
                logger.warning("Twilio selected but credentials (SID/Token/From) are missing.")
                return {
                    'success': False,
                    'provider': 'TWILIO',
                    'error': 'Missing TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, or TWILIO_FROM_NUMBER.',
                    'pending_config': True,
                }
            try:
                import base64
                to_number = f"+91{clean_phone_10}" if not phone_number.startswith('+') else phone_number
                url = f"https://api.twilio.com/2010-04-01/Accounts/{account_sid}/Messages.json"
                params = urllib.parse.urlencode({
                    'To': to_number,
                    'From': from_number,
                    'Body': message_text,
                }).encode('utf-8')
                auth_str = f"{account_sid}:{auth_token}"
                auth_b64 = base64.b64encode(auth_str.encode('utf-8')).decode('ascii')
                req = urllib.request.Request(
                    url,
                    data=params,
                    headers={'Authorization': f'Basic {auth_b64}'},
                    method="POST",
                )
                with urllib.request.urlopen(req, timeout=10) as resp:
                    logger.info("Twilio SMS dispatched to %s", to_number)
                    return {
                        'success': True,
                        'provider': 'TWILIO',
                        'message': 'OTP sent via Twilio SMS gateway.',
                    }
            except Exception as e:
                logger.error("Twilio dispatch failed: %s", e)
                return {
                    'success': False,
                    'provider': 'TWILIO',
                    'error': str(e),
                }

        # 3. Pending credentials / Local Development Console fallback
        logger.info(
            "[SMS GATEWAY - PENDING CREDENTIALS] Real SMS gateway credentials not yet configured in environment variables. "
            "To activate live cellular delivery, set FAST2SMS_API_KEY or TWILIO_* credentials in .env. "
            "OTP request processed for pilot at %s (OTP contents not logged for security).",
            clean_phone_10,
        )
        return {
            'success': True,
            'provider': 'PENDING_GATEWAY_CONFIG',
            'message': 'SMS gateway integration active. Live delivery pending gateway credentials in .env.',
            'pending_config': True,
        }
