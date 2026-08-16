import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
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

  static Future<({List<ChatMessage> messages, bool hasMore})> listMessages(
    String token,
    String conversationId, {
    int limit = 50,
    int? before,
  }) async {
    final q = <String, String>{
      'limit': '$limit',
      if (before != null) 'before': '$before',
    };
    final res = await http.get(
      _u('/conversations/$conversationId/messages').replace(queryParameters: q),
      headers: await _headers(token),
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body);
      final list = (body is List) ? body : (body['messages'] as List? ?? const []);
      final hasMore = body is Map<String, dynamic> ? (body['hasMore'] == true) : false;
      return (
        messages: list
            .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
        hasMore: hasMore,
      );
    }
    throw ApiException(res);
  }

  static Future<void> markRead(String token, String conversationId) async {
    await http.post(
      _u('/conversations/$conversationId/read'),
      headers: await _headers(token),
    );
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

  static Future<({String key, String url})> uploadImage(
    String token,
    String conversationId,
    String filePath, {
    String? contentType,
  }) async {
    final uri = _u('/uploads/image');
    final req = http.MultipartRequest('POST', uri);
    req.headers['Authorization'] = 'Bearer $token';
    req.fields['conversationId'] = conversationId;
    final name = p.basename(filePath);
    final mime = contentType ?? _guessImageMime(name);
    req.files.add(await http.MultipartFile.fromPath(
      'file',
      filePath,
      filename: name.contains('.') ? name : 'photo.jpg',
      contentType: MediaType.parse(mime),
    ));
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (key: body['key'] as String, url: body['url'] as String);
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

  static String _guessImageMime(String name) {
    switch (p.extension(name).toLowerCase()) {
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      case '.heif':
        return 'image/heif';
      default:
        return 'image/jpeg';
    }
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