"""
URL configuration for KKRTC - Where Is My Bus?
"""
from django.contrib import admin
from django.urls import include, path
from django.http import JsonResponse
from django.db import connection

def health_check(request):
    db_status = "connected"
    try:
        connection.ensure_connection()
    except Exception as e:
        db_status = f"disconnected: {type(e).__name__}"
        return JsonResponse({
            "status": "unhealthy",
            "service": "KKRTC - Where Is My Bus? API",
            "version": "1.0.0",
            "database": db_status
        }, status=503)

    return JsonResponse({
        "status": "healthy",
        "service": "KKRTC - Where Is My Bus? API",
        "version": "1.0.0",
        "database": db_status
    })

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/health/', health_check, name='api-health'),
    path('api/accounts/', include('apps.accounts.urls')),
    path('api/trips/', include('apps.trips.urls')),
    path('api/routes/', include('apps.routes.urls')),
]
