import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../app_routes.dart';
import '../config/api_config.dart';
import 'app_navigator.dart';
import 'auth_storage.dart';

class ApiClient {
  const ApiClient._();

  static bool _handlingForbidden = false;

  static bool _hasAuthHeader(RequestOptions options) {
    final dynamic header =
        options.headers['Authorization'] ?? options.headers['authorization'];
    return header != null && header.toString().trim().isNotEmpty;
  }

  static Future<void> _handleForbidden(RequestOptions requestOptions) async {
    if (_handlingForbidden) {
      return;
    }

    final bool hasAuthContext =
        _hasAuthHeader(requestOptions) || AuthStorage.hasToken;
    if (!hasAuthContext) {
      return;
    }

    _handlingForbidden = true;
    try {
      await AuthStorage.clear();
      final NavigatorState? navigator = AppNavigator.navigatorKey.currentState;
      if (navigator != null) {
        navigator.pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
      }
    } finally {
      _handlingForbidden = false;
    }
  }

  /// Matches the React logic:
  /// opt == 1 -> /guard, otherwise -> /admin
  static Dio create({required int opt, String? token}) {
    final String baseUrl = opt == 1
        ? '${ApiConfig.serverUrl}/guard'
        : '${ApiConfig.serverUrl}/admin';

    final Map<String, String> headers = {};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    final Dio dio = Dio(
      BaseOptions(
        baseUrl: baseUrl,
        headers: headers,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 20),
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onError: (DioException err, ErrorInterceptorHandler handler) async {
          if (err.response?.statusCode == 403) {
            await _handleForbidden(err.requestOptions);
          }
          handler.next(err);
        },
      ),
    );

    return dio;
  }
}
