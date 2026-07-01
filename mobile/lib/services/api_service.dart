import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'config.dart';

class ApiService {
  static Future<Map<String, String>> _headers(String? token) async {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (token != null) h['Authorization'] = 'Bearer $token';
    return h;
  }

  static Uri _u(String path) => Uri.parse('${Config.baseUrl}/api$path');

  static Future<AuthResult> register({
    required String username,
    required String fullName,
    required String email,
    required String password,
  }) async {
    final res = await http.post(
      _u('/auth/register'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'fullName': fullName,
        'email': email,
        'password': password,
      }),
    );
    if (res.statusCode == 201 || res.statusCode == 200) {
      return AuthResult.fromJson(jsonDecode(res.body));
    }
    throw ApiException(res);
  }

  static Future<AuthResult> login({
    required String login,
    required String password,
    String? fcmToken,
  }) async {
    final res = await http.post(
      _u('/auth/login'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'login': login, 'password': password, if (fcmToken != null) 'fcmToken': fcmToken}),
    );
    // NestJS POST handlers return 201 by default; accept any 2xx.
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return AuthResult.fromJson(jsonDecode(res.body));
    }
    throw ApiException(res);
  }

  static Future<User> getUser(String token, String username) async {
    final res = await http.get(_u('/users/$username'), headers: await _headers(token));
    if (res.statusCode == 200) return User.fromJson(jsonDecode(res.body));
    throw ApiException(res);
  }

  static Future<List<Conversation>> listConversations(String token) async {
    final res = await http.get(_u('/conversations'), headers: await _headers(token));
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List;
      return list.map((e) => Conversation.fromJson(e as Map<String, dynamic>)).toList();
    }
    throw ApiException(res);
  }

  static Future<Conversation> createPrivate(String token, String userId) async {
    final res = await http.post(
      _u('/conversations/private'),
      headers: await _headers(token),
      body: jsonEncode({'userId': userId}),
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      return Conversation.fromJson(jsonDecode(res.body));
    }
    throw ApiException(res);
  }

  static Future<Conversation> createGroup(
    String token, {
    String? title,
    required List<String> memberIds,
  }) async {
    final res = await http.post(
      _u('/conversations/group'),
      headers: await _headers(token),
      body: jsonEncode({if (title != null) 'title': title, 'memberIds': memberIds}),
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      return Conversation.fromJson(jsonDecode(res.body));
    }
    throw ApiException(res);
  }

  static Future<void> registerDevice(String token, String fcmToken, {String? platform}) async {
    await http.post(
      _u('/devices/register'),
      headers: await _headers(token),
      body: jsonEncode({'token': fcmToken, if (platform != null) 'platform': platform}),
    );
  }

  static Future<void> unregisterDevice(String token, String fcmToken) async {
    await http.delete(
      _u('/devices/unregister'),
      headers: await _headers(token),
      body: jsonEncode({'token': fcmToken}),
    );
  }
}

class ApiException implements Exception {
  final http.Response response;
  ApiException(this.response);

  String get message {
    try {
      final body = jsonDecode(response.body);
      return (body['message'] ?? response.body) as String;
    } catch (_) {
      return 'Request failed (${response.statusCode})';
    }
  }

  @override
  String toString() => message;
}