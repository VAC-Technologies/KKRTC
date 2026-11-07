import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/models/user_model.dart';

/// Central persistent state storage using SharedPreferences.
/// Preserves non-sensitive navigation context, incomplete forms, theme preferences,
/// and user sessions across application restarts.
class AppStateStorage {
  static const String _keyUserRole = 'kkrtc_user_role';
  static const String _keyIsAuthenticated = 'kkrtc_is_authenticated';
  static const String _keyPhoneNumber = 'kkrtc_phone_number';
  static const String _keyPassengerTabIndex = 'kkrtc_passenger_tab_index';
  static const String _keyPilotRouteId = 'kkrtc_pilot_route_id';
  static const String _keyPilotBusId = 'kkrtc_pilot_bus_id';
  static const String _keyPilotJourneyConfirmed =
      'kkrtc_pilot_journey_confirmed';
  static const String _keyPilotActiveTripId = 'kkrtc_pilot_active_trip_id';
  static const String _keySearchSource = 'kkrtc_search_source';
  static const String _keySearchDestination = 'kkrtc_search_destination';
  static const String _keyApiBaseUrl = 'kkrtc_api_base_url';
  static const String _keyThemeMode = 'kkrtc_theme_mode';
  static const String _keyAccessToken = 'kkrtc_jwt_access';
  static const String _keyRefreshToken = 'kkrtc_jwt_refresh';

  static SharedPreferences? _prefs;

  /// Global notifier allowing UI components to listen to theme changes.
  static final ValueNotifier<ThemeMode> themeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.light);

  /// Internal getter ensuring preferences instance is initialized.
  static Future<SharedPreferences> get _instance async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Inject or override prefs for testing.
  @visibleForTesting
  static void setMockInitialValues(Map<String, Object> values) {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues(values);
    _prefs = null;
  }

  // ================= THEME PREFERENCE =================

  /// Initializes the stored theme preference at app boot.
  static Future<void> initTheme() async {
    final mode = await getThemeMode();
    themeNotifier.value = mode;
  }

  /// Saves the selected theme mode (light, dark, or system).
  static Future<void> saveThemeMode(ThemeMode mode) async {
    final prefs = await _instance;
    await prefs.setString(_keyThemeMode, mode.name);
    themeNotifier.value = mode;
  }

  /// Retrieves the saved theme mode (defaults to light).
  static Future<ThemeMode> getThemeMode() async {
    final prefs = await _instance;
    final val = prefs.getString(_keyThemeMode);
    if (val == ThemeMode.dark.name) return ThemeMode.dark;
    if (val == ThemeMode.system.name) return ThemeMode.system;
    return ThemeMode.light;
  }

  // ================= ROLE & AUTHENTICATION =================

  /// Persists the selected user role (Passenger or Pilot).
  static Future<void> saveRole(UserRole role) async {
    final prefs = await _instance;
    await prefs.setString(_keyUserRole, role.name);
  }

  /// Retrieves the saved user role if set.
  static Future<UserRole?> getRole() async {
    final prefs = await _instance;
    final value = prefs.getString(_keyUserRole);
    if (value == null) return null;
    return value == UserRole.pilot.name ? UserRole.pilot : UserRole.passenger;
  }

  /// Saves the authenticated state and associated phone number.
  static Future<void> saveAuthenticatedSession({
    required UserRole role,
    required String phoneNumber,
  }) async {
    final prefs = await _instance;
    await Future.wait([
      prefs.setString(_keyUserRole, role.name),
      prefs.setBool(_keyIsAuthenticated, true),
      prefs.setString(_keyPhoneNumber, phoneNumber),
    ]);
  }

  /// Checks whether a valid session was previously established.
  static Future<bool> isAuthenticated() async {
    final prefs = await _instance;
    return prefs.getBool(_keyIsAuthenticated) ?? false;
  }

  /// Retrieves the stored phone number.
  static Future<String?> getPhoneNumber() async {
    final prefs = await _instance;
    return prefs.getString(_keyPhoneNumber);
  }

  // ================= JWT TOKENS =================

  /// Stores JWT access and refresh tokens.
  static Future<void> saveTokens({
    required String access,
    required String refresh,
  }) async {
    final prefs = await _instance;
    await Future.wait([
      prefs.setString(_keyAccessToken, access),
      prefs.setString(_keyRefreshToken, refresh),
    ]);
  }

  /// Retrieves the stored JWT access token.
  static Future<String?> getAccessToken() async {
    final prefs = await _instance;
    return prefs.getString(_keyAccessToken);
  }

  /// Retrieves the stored JWT refresh token.
  static Future<String?> getRefreshToken() async {
    final prefs = await _instance;
    return prefs.getString(_keyRefreshToken);
  }

  /// Clears stored JWT tokens.
  static Future<void> clearTokens() async {
    final prefs = await _instance;
    await Future.wait([
      prefs.remove(_keyAccessToken),
      prefs.remove(_keyRefreshToken),
    ]);
  }

  // ================= NAVIGATION CONTEXT =================

  /// Saves the current tab index inside [PassengerMainScreen].
  static Future<void> savePassengerTabIndex(int index) async {
    final prefs = await _instance;
    await prefs.setInt(_keyPassengerTabIndex, index);
  }

  /// Retrieves the last visited passenger tab index (defaults to 0: Home).
  static Future<int> getPassengerTabIndex() async {
    final prefs = await _instance;
    return prefs.getInt(_keyPassengerTabIndex) ?? 0;
  }

  // ================= PILOT TRIP FORM PERSISTENCE =================

  /// Persists pilot draft inputs (Route ID, Bus ID, and confirmation state).
  static Future<void> savePilotForm({
    required String routeId,
    required String busId,
    required bool isConfirmed,
  }) async {
    final prefs = await _instance;
    await Future.wait([
      prefs.setString(_keyPilotRouteId, routeId),
      prefs.setString(_keyPilotBusId, busId),
      prefs.setBool(_keyPilotJourneyConfirmed, isConfirmed),
    ]);
  }

  /// Retrieves draft inputs previously entered by the pilot.
  static Future<Map<String, dynamic>> getPilotForm() async {
    final prefs = await _instance;
    return {
      'routeId': prefs.getString(_keyPilotRouteId) ?? '',
      'busId': prefs.getString(_keyPilotBusId) ?? '',
      'isConfirmed': prefs.getBool(_keyPilotJourneyConfirmed) ?? false,
    };
  }

  /// Persists the active trip ID only when verified with the backend.
  static Future<void> savePilotActiveTripId(int? tripId) async {
    final prefs = await _instance;
    if (tripId == null) {
      await prefs.remove(_keyPilotActiveTripId);
    } else {
      await prefs.setInt(_keyPilotActiveTripId, tripId);
    }
  }

  /// Retrieves the previously recorded active trip ID.
  static Future<int?> getPilotActiveTripId() async {
    final prefs = await _instance;
    return prefs.getInt(_keyPilotActiveTripId);
  }

  // ================= PASSENGER SEARCH PERSISTENCE =================

  /// Persists recent search source and destination drafts.
  static Future<void> saveSearchQuery({
    String? source,
    String? destination,
  }) async {
    final prefs = await _instance;
    if (source != null) await prefs.setString(_keySearchSource, source);
    if (destination != null) {
      await prefs.setString(_keySearchDestination, destination);
    }
  }

  /// Retrieves recent draft search terms.
  static Future<Map<String, String>> getSearchQuery() async {
    final prefs = await _instance;
    return {
      'source': prefs.getString(_keySearchSource) ?? '',
      'destination': prefs.getString(_keySearchDestination) ?? '',
    };
  }

  // ================= API CONFIGURATION =================

  /// Persists the custom API base URL for physical device network testing.
  static Future<void> saveBaseUrl(String url) async {
    final prefs = await _instance;
    await prefs.setString(_keyApiBaseUrl, url.trim());
  }

  /// Retrieves the saved API base URL if customized.
  static Future<String?> getBaseUrl() async {
    final prefs = await _instance;
    final val = prefs.getString(_keyApiBaseUrl);
    if (val != null && val.trim().isNotEmpty) {
      return val.trim();
    }
    return null;
  }

  // ================= SESSION CLEANUP =================

  /// Logs the user out by clearing session authentication, active trip,
  /// tokens, and draft state while safely allowing a fresh login.
  static Future<void> clearSession() async {
    final prefs = await _instance;
    await Future.wait([
      prefs.remove(_keyIsAuthenticated),
      prefs.remove(_keyPhoneNumber),
      prefs.remove(_keyPassengerTabIndex),
      prefs.remove(_keyPilotActiveTripId),
      prefs.remove(_keyPilotJourneyConfirmed),
      prefs.remove(_keyAccessToken),
      prefs.remove(_keyRefreshToken),
      prefs.remove(_keyUserRole),
    ]);
  }

  /// Complete reset for test isolation or full app data wipe.
  static Future<void> clearAll() async {
    final prefs = await _instance;
    await prefs.clear();
  }
}
