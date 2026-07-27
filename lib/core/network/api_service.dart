import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

// Global logout callback — set by router
typedef LogoutCallback = void Function();
LogoutCallback? onUnauthorized;

class ApiService {
  late final Dio _dio;
  final _storage = const FlutterSecureStorage();
  Future<bool>? _refreshFuture;

  ApiService() {
    _dio = Dio(BaseOptions(
      baseUrl:        AppConstants.baseUrl,
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      sendTimeout:    const Duration(seconds: 12),
      headers:        {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        try {
          final token = await _storage
              .read(key: AppConstants.tokenKey)
              .timeout(const Duration(seconds: 2), onTimeout: () => null);
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
        } catch (_) {}
        return handler.next(options);
      },
      onError: (error, handler) async {
        final path = error.requestOptions.path;
        if (path.contains('/auth/login') || path.contains('/auth/google') || path.contains('/auth/refresh-token')) {
          return handler.next(error);
        }

        if (error.response?.statusCode == 401) {
          try {
            final refreshed = await _sharedRefresh()
                .timeout(const Duration(seconds: 8), onTimeout: () => false);
            if (refreshed) {
              final token = await _storage.read(key: AppConstants.tokenKey);
              error.requestOptions.headers['Authorization'] = 'Bearer $token';
              final retry = await _dio.fetch(error.requestOptions);
              return handler.resolve(retry);
            }
          } catch (_) {}

          await _storage.deleteAll();
          onUnauthorized?.call();
        }

        return handler.next(error);
      },
    ));

  }

  Future<bool> _sharedRefresh() {
    _refreshFuture ??= _refreshToken().whenComplete(() => _refreshFuture = null);
    return _refreshFuture!;
  }

  Future<bool> _refreshToken() async {
    try {
      final token = await _storage.read(key: AppConstants.tokenKey);
      if (token == null) return false;
      final res = await Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      )).post(
        '${AppConstants.baseUrl}/auth/refresh-token',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      if (res.data['success'] == true) {
        await _storage.write(key: AppConstants.tokenKey, value: res.data['data']['token']);
        return true;
      }
      return false;
    } catch (_) { return false; }
  }

  Future<Response> get(String path, {Map<String, dynamic>? params}) =>
      _dio.get(path, queryParameters: params);

  Future<Response> post(String path, {dynamic data}) =>
      _dio.post(path, data: data);

  Future<Response> put(String path, {dynamic data}) =>
      _dio.put(path, data: data);

  Future<Response> delete(String path) =>
      _dio.delete(path);

  Future<Response> uploadMultipart(String path, {required File file, required String mimeType}) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: file.path.split('/').last, contentType: DioMediaType.parse(mimeType)),
    });
    return _dio.post(path, data: form, options: Options(contentType: 'multipart/form-data'));
  }

  Future<void> saveToken(String token) => _storage.write(key: AppConstants.tokenKey, value: token);
  Future<void> clearToken() async {
    await _storage.delete(key: AppConstants.tokenKey);
  }
  Future<String?> getToken()           => _storage.read(key: AppConstants.tokenKey);
}