import '../models/user.dart';
import 'api_service.dart';

class AuthService {
  final ApiService _api = ApiService();

  Future<AuthResult> register({
    required String email,
    required String username,
    required String password,
  }) async {
    final response = await _api.post('/api/auth/register', {
      'email': email,
      'username': username,
      'password': password,
    });

    if (response.isSuccess) {
      return AuthResult(success: true, message: 'Registration successful');
    } else {
      final error = response.json?['error'] ?? 'Registration failed';
      return AuthResult(success: false, message: error);
    }
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final response = await _api.post('/api/auth/login', {
      'email': email,
      'password': password,
    });

    if (response.isSuccess) {
      final data = response.json;
      if (data != null && data['user'] != null) {
        final user = User.fromJson(data['user'] as Map<String, dynamic>);
        return AuthResult(success: true, user: user);
      }
      return AuthResult(success: true);
    } else {
      final error = response.json?['error'] ?? 'Login failed';
      return AuthResult(success: false, message: error);
    }
  }

  Future<AuthResult> logout() async {
    final response = await _api.post('/api/auth/logout', {});
    await _api.clearSession();
    return AuthResult(success: response.isSuccess);
  }

  Future<User?> getCurrentUser() async {
    // セッションクッキーを読み込み
    await _api.getSessionCookie();

    final response = await _api.get('/api/auth/me');

    if (response.isSuccess) {
      final data = response.json;
      if (data != null && data['user'] != null) {
        return User.fromJson(data['user'] as Map<String, dynamic>);
      }
    }
    return null;
  }
}

class AuthResult {
  final bool success;
  final String? message;
  final User? user;

  AuthResult({
    required this.success,
    this.message,
    this.user,
  });
}
