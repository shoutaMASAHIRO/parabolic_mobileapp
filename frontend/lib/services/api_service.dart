import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

// 条件付きインポート: Webの場合のみBrowserClientを使用
import 'api_client_stub.dart'
    if (dart.library.html) 'api_client_web.dart' as platform_client;

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  String? _sessionCookie;

  // プラットフォームに応じたHTTPクライアントを作成
  http.Client _createClient() {
    return platform_client.createClient();
  }

  Future<void> setSessionCookie(String cookie) async {
    _sessionCookie = cookie;
    // モバイルのみローカル保存
    if (!kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('session_cookie', cookie);
    }
  }

  Future<String?> getSessionCookie() async {
    if (_sessionCookie != null) return _sessionCookie;
    // モバイルのみローカルから読み込み
    if (!kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      _sessionCookie = prefs.getString('session_cookie');
    }
    return _sessionCookie;
  }

  Future<void> clearSession() async {
    _sessionCookie = null;
    if (!kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('session_cookie');
    }
  }

  Future<Map<String, String>> _buildHeaders({bool withJson = true}) async {
    final headers = <String, String>{};
    if (withJson) {
      headers['Content-Type'] = 'application/json';
    }
    // Webの場合はブラウザがCookieを自動管理するのでヘッダー不要
    if (!kIsWeb) {
      // SharedPreferencesからCookieを読み込む
      final cookie = await getSessionCookie();
      if (cookie != null) {
        headers['Cookie'] = cookie;
      }
    }
    return headers;
  }

  void _extractCookie(http.Response response) {
    // Webではブラウザが自動管理するのでスキップ
    if (kIsWeb) return;

    final setCookie = response.headers['set-cookie'];
    if (setCookie != null) {
      final match = RegExp(r'connect\.sid=[^;]+').firstMatch(setCookie);
      if (match != null) {
        setSessionCookie(match.group(0)!);
      }
    }
  }

  Future<ApiResponse> get(String endpoint) async {
    final client = _createClient();
    try {
      final headers = await _buildHeaders(withJson: false);
      final response = await client.get(
        Uri.parse('${AppConfig.apiUrl}$endpoint'),
        headers: headers,
      );
      _extractCookie(response);
      return ApiResponse(
        statusCode: response.statusCode,
        body: response.body,
        isSuccess: response.statusCode >= 200 && response.statusCode < 300,
      );
    } catch (e) {
      return ApiResponse(
        statusCode: 0,
        body: e.toString(),
        isSuccess: false,
      );
    } finally {
      client.close();
    }
  }

  Future<ApiResponse> post(String endpoint, Map<String, dynamic> data) async {
    final client = _createClient();
    try {
      final headers = await _buildHeaders();
      final response = await client.post(
        Uri.parse('${AppConfig.apiUrl}$endpoint'),
        headers: headers,
        body: jsonEncode(data),
      );
      _extractCookie(response);
      return ApiResponse(
        statusCode: response.statusCode,
        body: response.body,
        isSuccess: response.statusCode >= 200 && response.statusCode < 300,
      );
    } catch (e) {
      return ApiResponse(
        statusCode: 0,
        body: e.toString(),
        isSuccess: false,
      );
    } finally {
      client.close();
    }
  }

  Future<ApiResponse> put(String endpoint, Map<String, dynamic> data) async {
    final client = _createClient();
    try {
      final headers = await _buildHeaders();
      final response = await client.put(
        Uri.parse('${AppConfig.apiUrl}$endpoint'),
        headers: headers,
        body: jsonEncode(data),
      );
      _extractCookie(response);
      return ApiResponse(
        statusCode: response.statusCode,
        body: response.body,
        isSuccess: response.statusCode >= 200 && response.statusCode < 300,
      );
    } catch (e) {
      return ApiResponse(
        statusCode: 0,
        body: e.toString(),
        isSuccess: false,
      );
    } finally {
      client.close();
    }
  }

  Future<ApiResponse> delete(String endpoint) async {
    final client = _createClient();
    try {
      final headers = await _buildHeaders(withJson: false);
      final response = await client.delete(
        Uri.parse('${AppConfig.apiUrl}$endpoint'),
        headers: headers,
      );
      _extractCookie(response);
      return ApiResponse(
        statusCode: response.statusCode,
        body: response.body,
        isSuccess: response.statusCode >= 200 && response.statusCode < 300,
      );
    } catch (e) {
      return ApiResponse(
        statusCode: 0,
        body: e.toString(),
        isSuccess: false,
      );
    } finally {
      client.close();
    }
  }
}

class ApiResponse {
  final int statusCode;
  final String body;
  final bool isSuccess;

  ApiResponse({
    required this.statusCode,
    required this.body,
    required this.isSuccess,
  });

  Map<String, dynamic>? get json {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  List<dynamic>? get jsonList {
    try {
      return jsonDecode(body) as List<dynamic>;
    } catch (e) {
      return null;
    }
  }
}
