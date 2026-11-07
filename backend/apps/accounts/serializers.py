import re
from rest_framework import serializers

from apps.accounts.models import UserProfile


def clean_phone_number(raw_phone: str) -> str:
    """
    Strips non-digit characters and ensures a valid 10-digit Indian phone number.
    """
    digits = re.sub(r'\D', '', str(raw_phone))
    if len(digits) > 10 and digits.startswith('91'):
        digits = digits[2:]
    if len(digits) != 10:
        raise serializers.ValidationError('Mobile number must be exactly 10 digits.')
    return digits


class SendOtpSerializer(serializers.Serializer):
    phone_number = serializers.CharField(max_length=20)

    def validate_phone_number(self, value):
        return clean_phone_number(value)


class VerifyOtpSerializer(serializers.Serializer):
    phone_number = serializers.CharField(max_length=20)
    otp = serializers.CharField(max_length=6, min_length=6)

    def validate_phone_number(self, value):
        return clean_phone_number(value)

    def validate_otp(self, value):
        val = value.strip()
        if not val.isdigit() or len(val) != 6:
            raise serializers.ValidationError('OTP must be exactly 6 numeric digits.')
        return val


class UserProfileSerializer(serializers.ModelSerializer):
    username = serializers.CharField(source='user.username', read_only=True)
    user_id = serializers.IntegerField(source='user.id', read_only=True)

    class Meta:
        model = UserProfile
        fields = (
            'id',
            'user_id',
            'username',
            'role',
            'phone_number',
            'badge_number',
            'is_authorized_pilot',
        )
