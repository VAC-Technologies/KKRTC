import '../storage/app_state_storage.dart';

/// Centralized API Configuration for KKRTC
class ApiConfig {
  // Base URLs
  // Cloud Production deployment URL (Render)
  static const String cloudProductionBaseUrl =
      'https://kkrtc-backend.onrender.com/api';
  // Android Emulator default is 10.0.2.2 to access host machine
  static const String defaultEmulatorBaseUrl = 'http://10.0.2.2:8000/api';
  static const String defaultLocalhostBaseUrl = 'http://172.17.37.151:8000/api';

  // Environment override via --dart-define=API_BASE_URL=...
  static const String envBaseUrl = String.fromEnvironment('API_BASE_URL');

  // Demo Pilot Mode flag (Default: false)
  static bool demoPilotMode =
      const bool.fromEnvironment('DEMO_PILOT_MODE', defaultValue: false);

  // Configurable active base URL (defaults to cloud deployment for real phone connectivity)
  static String _activeBaseUrl = envBaseUrl.isNotEmpty
      ? envBaseUrl
      : cloudProductionBaseUrl;

  static String get activeBaseUrl => _activeBaseUrl;

  static set activeBaseUrl(String url) {
    final trimmed = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.isNotEmpty) {
      _activeBaseUrl = trimmed.endsWith('/api') ? trimmed : '$trimmed/api';
    }
  }

  /// Initializes activeBaseUrl from persistent storage if previously configured.
  static Future<void> initialize() async {
    if (envBaseUrl.isNotEmpty) {
      activeBaseUrl = envBaseUrl;
      return;
    }
    final saved = await AppStateStorage.getBaseUrl();
    if (saved != null && saved.isNotEmpty) {
      activeBaseUrl = saved;
    }
  }

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 15);

  // Authentication Endpoints
  static const String pilotSendOtpEndpoint = '/accounts/pilot/send-otp/';
  static const String pilotVerifyOtpEndpoint = '/accounts/pilot/verify-otp/';
  static const String demoPilotSessionEndpoint = '/accounts/pilot/demo-session/';
  static const String pilotProfileEndpoint = '/accounts/pilot/me/';
  static const String tokenRefreshEndpoint = '/accounts/token/refresh/';
  static const String loginEndpoint = '/accounts/pilot/send-otp/';
  static const String verifyOtpEndpoint = '/accounts/pilot/verify-otp/';
  static const String userProfileEndpoint = '/accounts/pilot/me/';

  // Bus & Route Endpoints
  static const String authorizedPilotsEndpoint = '/accounts/pilots/';
  static const String busesEndpoint = '/buses/';
  static const String routesEndpoint = '/routes/';
  static const String locationSuggestionsEndpoint =
      '/routes/locations/suggestions/';
  static const String tripsEndpoint = '/trips/';
  static const String activeTripsEndpoint = '/trips/active/';

  // Tracking Endpoints
  static const String liveLocationEndpoint = '/passenger/trips/';
  static const String passengerGpsSubmissionEndpoint = '/passenger/location/';
  static const String driverGpsSubmissionEndpoint = '/driver/location/';

  // Driver Endpoints
  static const String driverAssignedTripsEndpoint = '/driver/assigned-trips/';
  static const String driverStartTripEndpoint = '/trips/start/';
  static const String driverStopTripEndpoint = '/trips/end/';

  static Uri get activeTripsWebSocketUri {
    final apiUri = Uri.parse(activeBaseUrl);
    final basePath = apiUri.path.replaceFirst(RegExp(r'/api/?$'), '');
    return apiUri.replace(
      scheme: apiUri.scheme == 'https' ? 'wss' : 'ws',
      path: '$basePath/ws/active-trips/',
      query: null,
      fragment: null,
    );
  }
}
