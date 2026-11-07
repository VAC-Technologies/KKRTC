from django.contrib import admin

from apps.accounts.models import PilotOTP, UserProfile


@admin.register(UserProfile)
class UserProfileAdmin(admin.ModelAdmin):
    list_display = ('user', 'role', 'phone_number', 'badge_number', 'is_authorized_pilot')
    list_filter = ('role', 'is_authorized_pilot')
    search_fields = ('user__username', 'phone_number', 'badge_number')


@admin.register(PilotOTP)
class PilotOTPAdmin(admin.ModelAdmin):
    list_display = ('phone_number', 'created_at', 'expires_at', 'is_used', 'attempts')
    list_filter = ('is_used',)
    search_fields = ('phone_number',)
    readonly_fields = ('phone_number', 'otp_hash', 'created_at', 'expires_at', 'attempts')
