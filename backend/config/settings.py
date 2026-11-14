
"""
Django settings for KKRTC - Where Is My Bus? backend.
"""

import os
import sys
from pathlib import Path

from dotenv import load_dotenv
from django.core.exceptions import ImproperlyConfigured


BASE_DIR = Path(__file__).resolve().parent.parent

# Add apps directory to sys.path
sys.path.insert(0, str(BASE_DIR))
sys.path.insert(0, str(BASE_DIR / 'apps'))

load_dotenv(BASE_DIR / '.env')


# ---------------------------------------------------------------------------
# SECURITY CONFIGURATION
# ---------------------------------------------------------------------------

def get_secret_key(debug_mode: bool) -> str:
    """
    Retrieves SECRET_KEY from environment variables.
    Production requires a strong, unique SECRET_KEY.
    """

    key = os.getenv('SECRET_KEY', '').strip()

    if key:
        return key

    if debug_mode:
        return 'django-insecure-kkrtc-dev-local-only-key-not-for-production'

    raise ImproperlyConfigured(
        'The SECRET_KEY environment variable is required when DEBUG=False. '
        'Configure a strong, unique SECRET_KEY in your production environment.'
    )


DEBUG = os.getenv('DEBUG', 'False').strip().lower() in (
    'true', '1', 'yes'
)

SECRET_KEY = get_secret_key(DEBUG)


# ---------------------------------------------------------------------------
# DEVELOPMENT-ONLY OTP CONSOLE
# ---------------------------------------------------------------------------

DEVELOPMENT_OTP_CONSOLE = (
    os.getenv('DEVELOPMENT_OTP_CONSOLE', 'False').strip().lower()
    in ('true', '1', 'yes')
)


# ---------------------------------------------------------------------------
# DEMO PILOT MODE (Controlled Campus Testing Only)
# ---------------------------------------------------------------------------

DEMO_PILOT_MODE = (
    os.getenv('DEMO_PILOT_MODE', 'False').strip().lower()
    in ('true', '1', 'yes')
)


# ---------------------------------------------------------------------------
# ALLOWED HOSTS
# ---------------------------------------------------------------------------

default_allowed_hosts = 'localhost,127.0.0.1,0.0.0.0,10.0.2.2,kkrtc-backend.onrender.com,.onrender.com'
configured_hosts = os.getenv('ALLOWED_HOSTS', default_allowed_hosts)

ALLOWED_HOSTS = (
    ['*']
    if DEBUG
    else [
        host.strip()
        for host in configured_hosts.split(',')
        if host.strip()
    ]
)

# Automatically add Render host if present in environment
render_host = os.getenv('RENDER_EXTERNAL_HOSTNAME', '').strip()
if render_host and '*' not in ALLOWED_HOSTS and render_host not in ALLOWED_HOSTS:
    ALLOWED_HOSTS.append(render_host)


# ---------------------------------------------------------------------------
# INSTALLED APPLICATIONS
# ---------------------------------------------------------------------------

INSTALLED_APPS = [
    'daphne',

    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',

    # Third-party applications
    'rest_framework',
    'rest_framework_simplejwt',
    'corsheaders',
    'channels',

    # KKRTC applications
    'apps.accounts',
    'apps.buses',
    'apps.routes',
    'apps.trips',
    'apps.tracking',
    'apps.eta',
    'apps.notifications',
]


# ---------------------------------------------------------------------------
# MIDDLEWARE
# ---------------------------------------------------------------------------

MIDDLEWARE = [
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]


ROOT_URLCONF = 'config.urls'

WSGI_APPLICATION = 'config.wsgi.application'
ASGI_APPLICATION = 'config.asgi.application'


# ---------------------------------------------------------------------------
# TEMPLATES
# ---------------------------------------------------------------------------

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [BASE_DIR / 'templates'],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]


# ---------------------------------------------------------------------------
# DATABASE CONFIGURATION (PostgreSQL + PostGIS)
# ---------------------------------------------------------------------------

def get_database_config():
    """
    Constructs the database configuration dictionary.
    Supports standard 12-factor DATABASE_URL if present (e.g. Render/Heroku),
    falling back to individual POSTGRES_* environment variables.
    Enforces connect_timeout to prevent hanging connections.
    """
    db_url = os.getenv('DATABASE_URL', '').strip()
    if db_url:
        import urllib.parse
        parsed = urllib.parse.urlparse(db_url)
        path = parsed.path.lstrip('/')
        query = urllib.parse.parse_qs(parsed.query)
        options = {
            'connect_timeout': int(os.getenv('POSTGRES_CONNECT_TIMEOUT', '10')),
        }
        sslmode = query.get('sslmode', [os.getenv('POSTGRES_SSLMODE', 'require')])[0]
        if sslmode:
            options['sslmode'] = sslmode
        return {
            'ENGINE': 'django.db.backends.postgresql',
            'NAME': urllib.parse.unquote(path or 'postgres'),
            'USER': urllib.parse.unquote(parsed.username or ''),
            'PASSWORD': urllib.parse.unquote(parsed.password or ''),
            'HOST': parsed.hostname or 'localhost',
            'PORT': str(parsed.port or 5432),
            'CONN_MAX_AGE': int(os.getenv('POSTGRES_CONN_MAX_AGE', '60')),
            'OPTIONS': options,
        }

    host = os.getenv('POSTGRES_HOST', 'localhost')
    options = {
        'connect_timeout': int(os.getenv('POSTGRES_CONNECT_TIMEOUT', '10')),
    }
    sslmode = os.getenv(
        'POSTGRES_SSLMODE',
        'require' if host and host not in ('localhost', '127.0.0.1') else 'prefer'
    )
    if sslmode:
        options['sslmode'] = sslmode

    return {
        'ENGINE': 'django.db.backends.postgresql',
        'NAME': os.getenv('POSTGRES_DB', 'kkrtc_db'),
        'USER': os.getenv('POSTGRES_USER', 'kkrtc_user'),
        'PASSWORD': os.getenv('POSTGRES_PASSWORD', ''),
        'HOST': host,
        'PORT': os.getenv('POSTGRES_PORT', '5432'),
        'CONN_MAX_AGE': int(os.getenv('POSTGRES_CONN_MAX_AGE', '60')),
        'OPTIONS': options,
    }


DATABASES = {
    'default': get_database_config()
}


# ---------------------------------------------------------------------------
# PASSWORD VALIDATION
# ---------------------------------------------------------------------------

AUTH_PASSWORD_VALIDATORS = [
    {
        'NAME': 'django.contrib.auth.password_validation.UserAttributeSimilarityValidator'
    },
    {
        'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator'
    },
    {
        'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'
    },
    {
        'NAME': 'django.contrib.auth.password_validation.NumericPasswordValidator'
    },
]


# ---------------------------------------------------------------------------
# INTERNATIONALIZATION
# ---------------------------------------------------------------------------

LANGUAGE_CODE = 'en-us'
TIME_ZONE = 'Asia/Kolkata'

USE_I18N = True
USE_TZ = True


# ---------------------------------------------------------------------------
# STATIC FILES
# ---------------------------------------------------------------------------

STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'


# ---------------------------------------------------------------------------
# DEFAULT PRIMARY KEY
# ---------------------------------------------------------------------------

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'


# ---------------------------------------------------------------------------
# DJANGO REST FRAMEWORK
# ---------------------------------------------------------------------------

REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'rest_framework_simplejwt.authentication.JWTAuthentication',
    ),

    'DEFAULT_PERMISSION_CLASSES': (
        'rest_framework.permissions.IsAuthenticatedOrReadOnly',
    ),

    'DEFAULT_THROTTLE_RATES': {
        'anon': '100/minute',
        'user': '1000/minute',
        'demo_session': '10/minute',
    },
}


# ---------------------------------------------------------------------------
# CORS CONFIGURATION
# ---------------------------------------------------------------------------

CORS_ALLOW_ALL_ORIGINS = (
    os.getenv('CORS_ALLOW_ALL_ORIGINS', 'False').strip().lower()
    in ('true', '1', 'yes')
)

CORS_ALLOWED_ORIGINS = [
    origin.strip()
    for origin in os.getenv('CORS_ALLOWED_ORIGINS', '').split(',')
    if origin.strip()
]


# ---------------------------------------------------------------------------
# DJANGO CHANNELS
# ---------------------------------------------------------------------------

# In-memory channel layer is suitable for local development.
# We will configure Redis before production WebSocket deployment.

CHANNEL_LAYERS = {
    'default': {
        'BACKEND': 'channels.layers.InMemoryChannelLayer',
    },
}
