import 'package:dio/dio.dart';

import '../storage/app_state_storage.dart';
import 'api_config.dart';

/// Centralized Dio HTTP Client for KKRTC
class ApiClient {
  late final Dio _dio;

  ApiClient({String? baseUrl}) {
    _dio = Dio(
      BaseOptions(
        baseUrl: baseUrl ?? ApiConfig.activeBaseUrl,
        connectTimeout: ApiConfig.connectTimeout,
        receiveTimeout: ApiConfig.receiveTimeout,
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Dynamically ensure request uses the active configured baseUrl
          if (!options.path.startsWith('http')) {
            options.baseUrl = ApiConfig.activeBaseUrl;
          }

          final token = await AppStateStorage.getAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onResponse: (response, handler) {
          return handler.next(response);
        },
        onError: (DioException error, handler) async {
          final statusCode = error.response?.statusCode;
          final isRetry = error.requestOptions.extra['isRetry'] == true;
          final path = error.requestOptions.path;
          final isAuthEndpoint = path.contains('/accounts/token/refresh/') ||
              path.contains('/accounts/pilot/verify-otp/') ||
              path.contains('/accounts/pilot/send-otp/') ||
              path.contains('/accounts/pilot/demo-session/');

          // Attempt automatic token refresh on 401 for non-auth endpoints exactly once
          if (statusCode == 401 && !isRetry && !isAuthEndpoint) {
            final refreshToken = await AppStateStorage.getRefreshToken();
            if (refreshToken != null && refreshToken.isNotEmpty) {
              try {
                // Dedicated unintercepted client to avoid recursion
                final refreshDio = Dio(
                  BaseOptions(
                    baseUrl: ApiConfig.activeBaseUrl,
                    connectTimeout: ApiConfig.connectTimeout,
                    receiveTimeout: ApiConfig.receiveTimeout,
                    headers: {
                      'Content-Type': 'application/json',
                      'Accept': 'application/json',
                    },
                  ),
                );

                final refreshResponse = await refreshDio.post<Map<String, dynamic>>(
                  ApiConfig.tokenRefreshEndpoint,
                  data: {'refresh': refreshToken},
                );

                if (refreshResponse.statusCode == 200 && refreshResponse.data != null) {
                  final newAccessToken =
                      refreshResponse.data!['access'] as String?;
                  if (newAccessToken != null && newAccessToken.isNotEmpty) {
                    await AppStateStorage.saveTokens(
                      access: newAccessToken,
                      refresh: refreshToken,
                    );

                    // Mark request as retried and update bearer token
                    error.requestOptions.extra['isRetry'] = true;
                    error.requestOptions.headers['Authorization'] =
                        'Bearer $newAccessToken';

                    final retriedResponse =
                        await _dio.fetch(error.requestOptions);
                    return handler.resolve(retriedResponse);
                  }
                }
              } catch (_) {
                // Refresh failed: clear session safely requiring re-authentication
                await AppStateStorage.clearSession();
              }
            } else {
              await AppStateStorage.clearSession();
            }
          }

          return handler.next(error);
        },
      ),
    );
  }

  Dio get dio => _dio;

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return _dio.get<T>(
      path,
      queryParameters: queryParameters,
      options: options,
    );
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    return _dio.post<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
    );
  }
}
