import 'dart:developer' as developer;
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../core/network/api_client.dart';
import '../../core/network/api_config.dart';
import '../../core/storage/app_state_storage.dart';
import '../models/user_model.dart';

abstract class AuthRepository {
  static AuthRepository? _instance;

  static AuthRepository get instance {
    if (_instance != null) return _instance!;
    // Automatically switch to MockAuthRepository during automated Flutter test runs
    if (!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) {
      return MockAuthRepository();
    }
    return DjangoAuthRepository();
  }

  @visibleForTesting
  static set instance(AuthRepository? repo) {
    _instance = repo;
  }

  Future<bool> sendOtp(String phoneNumber);
  Future<UserModel> verifyOtp(String phoneNumber, String otp);
  Future<Map<String, dynamic>> loginDemoPilot();
  Future<UserModel?> getCurrentUser();
  Future<void> logout();
}

/// Real Django Authentication Repository with JWT tokens and OTP verification.
class DjangoAuthRepository implements AuthRepository {
  final ApiClient _client;

  DjangoAuthRepository({ApiClient? client}) : _client = client ?? ApiClient();

  @override
  Future<bool> sendOtp(String phoneNumber) async {
    final cleanDigits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    final phone10 = cleanDigits.length > 10
        ? cleanDigits.substring(cleanDigits.length - 10)
        : cleanDigits;

    try {
      final response = await _client.post<Map<String, dynamic>>(
        ApiConfig.pilotSendOtpEndpoint,
        data: {'phone_number': phone10},
      );
      if (response.statusCode == 200) {
        return true;
      }
      return false;
    } on DioException catch (e) {
      final err = e.response?.data;
      if (err is Map && err['error'] != null) {
        throw Exception(err['error']);
      }
      developer.log(
        'Error dispatching pilot OTP: ${e.message}',
        name: 'AuthRepository',
      );
      rethrow;
    }
  }

  @override
  Future<UserModel> verifyOtp(String phoneNumber, String otp) async {
    final cleanDigits = phoneNumber.replaceAll(RegExp(r'\D'), '');
    final phone10 = cleanDigits.length > 10
        ? cleanDigits.substring(cleanDigits.length - 10)
        : cleanDigits;

    try {
      final response = await _client.post<Map<String, dynamic>>(
        ApiConfig.pilotVerifyOtpEndpoint,
        data: {'phone_number': phone10, 'otp': otp.trim()},
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data!;
        final access = data['access'] as String?;
        final refresh = data['refresh'] as String?;

        if (access != null && refresh != null) {
          await AppStateStorage.saveTokens(access: access, refresh: refresh);
        }

        final userData = data['user'] as Map<String, dynamic>?;
        final user = UserModel(
          id: userData?['id']?.toString() ?? 'pilot_id',
          name: userData?['username'] ?? 'KKRTC Pilot',
          phoneNumber: phoneNumber,
          role: UserRole.pilot,
        );

        await AppStateStorage.saveAuthenticatedSession(
          role: UserRole.pilot,
          phoneNumber: phoneNumber,
        );

        return user;
      }
      throw Exception('Verification failed');
    } on DioException catch (e) {
      final err = e.response?.data;
      if (err is Map && err['error'] != null) {
        throw Exception(err['error']);
      }
      rethrow;
    }
  }

  @override
  Future<UserModel?> getCurrentUser() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        ApiConfig.pilotProfileEndpoint,
      );
      if (response.statusCode == 200 && response.data != null) {
        final d = response.data!;
        return UserModel(
          id: d['user_id']?.toString() ?? 'pilot',
          name: d['username'] ?? 'Pilot',
          phoneNumber: d['phone_number'] ?? '',
          role: UserRole.pilot,
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>> loginDemoPilot() async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        ApiConfig.demoPilotSessionEndpoint,
      );
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data!;
        final access = data['access'] as String?;
        final refresh = data['refresh'] as String?;

        if (access != null && refresh != null) {
          await AppStateStorage.saveTokens(access: access, refresh: refresh);
        }

        final pilotData = data['pilot'] as Map<String, dynamic>?;
        final phone = pilotData?['phone_number']?.toString() ?? '9876543210';
        await AppStateStorage.saveAuthenticatedSession(
          role: UserRole.pilot,
          phoneNumber: phone,
        );

        final busData = data['assigned_bus'] as Map<String, dynamic>?;
        final routeData = data['default_route'] as Map<String, dynamic>?;

        final busId = busData?['id']?.toString() ?? '1';
        final routeId = routeData?['id']?.toString() ?? '1';

        await AppStateStorage.savePilotForm(
          routeId: routeId,
          busId: busId,
          isConfirmed: true,
        );

        return data;
      }
      throw Exception('Failed to initialize demo pilot session.');
    } on DioException catch (e) {
      final err = e.response?.data;
      if (err is Map && err['error'] != null) {
        throw Exception(err['error']);
      }
      developer.log(
        'Error initiating demo pilot session: ${e.message}',
        name: 'AuthRepository',
      );
      rethrow;
    }
  }

  @override
  Future<void> logout() async {
    await AppStateStorage.clearSession();
  }
}

/// Fallback Mock Authentication Repository for test environments.
class MockAuthRepository implements AuthRepository {
  UserModel? _currentUser;

  @override
  Future<bool> sendOtp(String phoneNumber) async {
    await Future.delayed(const Duration(milliseconds: 600));
    return phoneNumber.length >= 10;
  }

  @override
  Future<UserModel> verifyOtp(String phoneNumber, String otp) async {
    await Future.delayed(const Duration(milliseconds: 700));
    _currentUser = UserModel(
      id: 'usr_demo_01',
      name: 'Ramesh Gouda',
      phoneNumber: phoneNumber,
      email: 'ramesh.gouda@example.com',
      role: UserRole.pilot,
    );
    await AppStateStorage.saveAuthenticatedSession(
      role: UserRole.pilot,
      phoneNumber: phoneNumber,
    );
    return _currentUser!;
  }

  @override
  Future<Map<String, dynamic>> loginDemoPilot() async {
    await AppStateStorage.saveTokens(
      access: 'mock_demo_access_token',
      refresh: 'mock_demo_refresh_token',
    );
    await AppStateStorage.saveAuthenticatedSession(
      role: UserRole.pilot,
      phoneNumber: '9876543210',
    );
    await AppStateStorage.savePilotForm(
      routeId: '1',
      busId: '1',
      isConfirmed: true,
    );
    return {
      'demo_mode': true,
      'pilot': {'username': 'Anil', 'phone_number': '9876543210'},
      'assigned_bus': {'id': 1, 'registration_number': 'KA-34-A-1001'},
      'default_route': {'id': 1, 'route_id': 'R001'},
    };
  }

  @override
  Future<UserModel?> getCurrentUser() async {
    return _currentUser ??
        const UserModel(
          id: 'usr_demo_01',
          name: 'Ramesh Gouda',
          phoneNumber: '+91 98450 12345',
          email: 'ramesh.gouda@example.com',
          role: UserRole.pilot,
        );
  }

  @override
  Future<void> logout() async {
    _currentUser = null;
    await AppStateStorage.clearSession();
  }
}
