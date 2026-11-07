import hashlib
from datetime import timedelta

from django.conf import settings
from django.contrib.auth.hashers import check_password, make_password
from django.db import models
from django.utils import timezone


class UserProfile(models.Model):
    class Role(models.TextChoices):
        PASSENGER = 'PASSENGER', 'Passenger'
        PILOT = 'PILOT', 'Pilot'

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='profile',
    )
    role = models.CharField(max_length=12, choices=Role.choices, default=Role.PASSENGER)
    phone_number = models.CharField(
        max_length=15,
        unique=True,
        null=True,
        blank=True,
        db_index=True,
        help_text='10-digit mobile number or E.164 format',
    )
    badge_number = models.CharField(
        max_length=32,
        blank=True,
        default='',
        help_text='Official KKRTC Pilot badge or employee number',
    )
    is_authorized_pilot = models.BooleanField(
        default=False,
        help_text='Whether this user is an authorized KKRTC pilot/driver',
    )

    def __str__(self):
        return f'{self.user.username} ({self.role}) - {self.phone_number or "No Phone"}'


class PilotOTP(models.Model):
    """
    Stores server-generated, cryptographically secure OTPs for pilot authentication.
    Enforces expiration, single-use, resend cooldown, and attempt limits.
    """
    phone_number = models.CharField(max_length=15, db_index=True)
    otp_hash = models.CharField(max_length=128)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    is_used = models.BooleanField(default=False)
    attempts = models.PositiveSmallIntegerField(default=0)
    max_attempts = models.PositiveSmallIntegerField(default=3)

    class Meta:
        ordering = ('-created_at',)
        verbose_name = 'Pilot OTP'
        verbose_name_plural = 'Pilot OTPs'

    @classmethod
    def create_for_phone(cls, phone_number, plain_otp, validity_minutes=5):
        """
        Hashes plain OTP and creates an unverified record.
        """
        expires_at = timezone.now() + timedelta(minutes=validity_minutes)
        otp_hash = make_password(plain_otp)
        return cls.objects.create(
            phone_number=phone_number,
            otp_hash=otp_hash,
            expires_at=expires_at,
        )

    @property
    def is_expired(self):
        return timezone.now() > self.expires_at

    def check_otp(self, plain_otp):
        """
        Verifies candidate OTP, increments attempt counter, and updates usage status.
        """
        if self.is_used:
            return False, 'This OTP has already been used. Please request a new one.'

        if self.is_expired:
            return False, 'This OTP has expired. Please request a new one.'

        if self.attempts >= self.max_attempts:
            return False, 'Maximum verification attempts exceeded. Please request a new OTP.'

        self.attempts += 1
        self.save(update_fields=['attempts'])

        if check_password(plain_otp, self.otp_hash):
            self.is_used = True
            self.save(update_fields=['is_used'])
            return True, 'OTP verified successfully.'

        remaining = self.max_attempts - self.attempts
        if remaining > 0:
            return False, f'Incorrect OTP. {remaining} attempt(s) remaining.'
        return False, 'Maximum verification attempts exceeded. Please request a new OTP.'
