"""
ASGI config for KKRTC backend.
"""
import os
from django.conf import settings
from django.core.asgi import get_asgi_application
from channels.auth import AuthMiddlewareStack
from channels.routing import ProtocolTypeRouter, URLRouter
from channels.security.websocket import OriginValidator

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')

django_asgi_app = get_asgi_application()

from apps.trips.routing import websocket_urlpatterns


class MobileAndBrowserOriginValidator(OriginValidator):
    """
    Validates WebSocket connections.
    - Allows native mobile clients (Flutter / Android / iOS) where Origin header is absent.
    - Validates browser clients against ALLOWED_HOSTS to prevent CSWSH attacks.
    """

    def valid_origin(self, parsed_origin):
        if parsed_origin is None:
            return True
        return super().valid_origin(parsed_origin)


def get_origin_validator(app):
    allowed_hosts = list(settings.ALLOWED_HOSTS)
    if settings.DEBUG and not allowed_hosts:
        allowed_hosts = ["localhost", "127.0.0.1", "[::1]"]
    return MobileAndBrowserOriginValidator(app, allowed_hosts)


application = ProtocolTypeRouter({
    "http": django_asgi_app,
    "websocket": get_origin_validator(
        AuthMiddlewareStack(URLRouter(websocket_urlpatterns))
    ),
})
