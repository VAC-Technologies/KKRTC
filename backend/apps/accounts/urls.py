from django.urls import path
from rest_framework_simplejwt.views import TokenRefreshView

from apps.accounts.views import (
    CurrentPilotProfileView,
    DemoPilotSessionView,
    PilotSendOtpView,
    PilotVerifyOtpView,
)

app_name = 'accounts'

urlpatterns = [
    path('pilot/send-otp/', PilotSendOtpView.as_view(), name='pilot-send-otp'),
    path('pilot/verify-otp/', PilotVerifyOtpView.as_view(), name='pilot-verify-otp'),
    path('pilot/demo-session/', DemoPilotSessionView.as_view(), name='pilot-demo-session'),
    path('pilot/me/', CurrentPilotProfileView.as_view(), name='pilot-profile'),
    path('token/refresh/', TokenRefreshView.as_view(), name='token-refresh'),
]
