import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import '../models/models.dart';

class AuthService {
  static const _kToken = 'auth_token';
  /// Public so the FCM background isolate can read the logged-in userId and
  /// open the right per-account [MessageStore] without the main isolate.
  static const kUserIdKey = 'auth_user_id';
  static const _kUserId = kUserIdKey;
  static const _kUsername = 'auth_username';

  String? _token;
  String? _userId;
  String? _username;

  String? get token => _token;
  String? get userId => _userId;
  String? get username => _username;
  bool get isAuthenticated => _token != null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_kToken);
    _userId = prefs.getString(_kUserId);
    _username = prefs.getString(_kUsername);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_token != null) {
      await prefs.setString(_kToken, _token!);
      await prefs.setString(_kUserId, _userId!);
      await prefs.setString(_kUsername, _username!);
    } else {
      await prefs.remove(_kToken);
      await prefs.remove(_kUserId);
      await prefs.remove(_kUsername);
    }
  }

  Future<AuthResult> register({
    required String username,
    required String fullName,
    required String email,
    required String password,
  }) async {
    final res = await ApiService.register(
      username: username,
      fullName: fullName,
      email: email,
      password: password,
    );
    _set(res);
    return res;
  }

  Future<AuthResult> login({required String login, required String password}) async {
    final res = await ApiService.login(login: login, password: password);
    _set(res);
    return res;
  }

  void _set(AuthResult res) {
    _token = res.accessToken;
    _userId = res.userId;
    _username = res.username;
    _persist();
  }

  Future<void> logout() async {
    _token = null;
    _userId = null;
    _username = null;
    await _persist();
  }
}