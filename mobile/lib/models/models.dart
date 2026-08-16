class User {
  final String id;
  final String username;
  final String fullName;
  final String? avatarUrl;
  final DateTime? lastSeenAt;

  User({
    required this.id,
    required this.username,
    required this.fullName,
    this.avatarUrl,
    this.lastSeenAt,
  });

  factory User.fromJson(Map<String, dynamic> j) => User(
        id: j['id'] as String,
        username: j['username'] as String,
        fullName: (j['fullName'] ?? j['full_name'] ?? '') as String,
        avatarUrl: j['avatarUrl'] as String?,
        lastSeenAt: j['lastSeenAt'] != null
            ? DateTime.tryParse(j['lastSeenAt'].toString())
            : null,
      );
}

class AuthResult {
  final String accessToken;
  final String userId;
  final String username;

  AuthResult({
    required this.accessToken,
    required this.userId,
    required this.username,
  });

  factory AuthResult.fromJson(Map<String, dynamic> j) => AuthResult(
        accessToken: j['accessToken'] as String,
        userId: (j['user'] as Map)['id'] as String,
        username: (j['user'] as Map)['username'] as String,
      );
}

enum ConversationType { private, group }

class ConversationMember {
  final String userId;
  final String role;
  final DateTime joinedAt;
  final String? username;
  final String? fullName;
  final String? avatarUrl;

  ConversationMember({
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.username,
    this.fullName,
    this.avatarUrl,
  });

  factory ConversationMember.fromJson(Map<String, dynamic> j) => ConversationMember(
        userId: j['userId'] as String,
        role: j['role'] as String,
        joinedAt: DateTime.tryParse(j['joinedAt'].toString()) ?? DateTime.now(),
        username: j['username'] as String?,
        fullName: j['fullName'] as String?,
        avatarUrl: j['avatarUrl'] as String?,
      );

  ConversationMember copyWith({String? avatarUrl}) {
    return ConversationMember(
      userId: userId,
      role: role,
      joinedAt: joinedAt,
      username: username,
      fullName: fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}

class Conversation {
  final String id;
  final ConversationType type;
  final String? title;
  final String? avatarUrl;
  final DateTime createdAt;
  final List<ConversationMember> members;
  final ChatMessage? lastMessage;
  final int unreadCount;

  Conversation({
    required this.id,
    required this.type,
    this.title,
    this.avatarUrl,
    required this.createdAt,
    required this.members,
    this.lastMessage,
    this.unreadCount = 0,
  });

  factory Conversation.fromJson(Map<String, dynamic> j) {
    final type = (j['type'] as String) == 'group'
        ? ConversationType.group
        : ConversationType.private;
    final members = (j['members'] as List)
        .map((m) => ConversationMember.fromJson(m as Map<String, dynamic>))
        .toList();
    final last = j['lastMessage'];
    return Conversation(
      id: j['id'] as String,
      type: type,
      title: j['title'] as String?,
      avatarUrl: j['avatarUrl'] as String?,
      createdAt: DateTime.tryParse(j['createdAt'].toString()) ?? DateTime.now(),
      members: members,
      lastMessage: last is Map<String, dynamic> ? ChatMessage.fromJson(last) : null,
      unreadCount: (j['unreadCount'] as num?)?.toInt() ?? 0,
    );
  }

  Conversation copyWith({
    ChatMessage? lastMessage,
    int? unreadCount,
    List<ConversationMember>? members,
    String? avatarUrl,
  }) {
    return Conversation(
      id: id,
      type: type,
      title: title,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdAt: createdAt,
      members: members ?? this.members,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

enum MessageType { text, sticker, gif, image, call }

MessageType parseMessageType(String? t) {
  switch (t) {
    case 'sticker':
      return MessageType.sticker;
    case 'gif':
      return MessageType.gif;
    case 'image':
      return MessageType.image;
    case 'call':
      return MessageType.call;
    default:
      return MessageType.text;
  }
}

class ChatMessage {
  final String id;
  final String conversationId;
  final MessageType type;
  final String? text;
  final String? media;
  final String? caption;
  final String senderId;
  final String? senderUsername;
  final String? senderFullName;
  final int createdAt;
  bool delivered;

  ChatMessage({
    required this.id,
    required this.conversationId,
    required this.type,
    this.text,
    this.media,
    this.caption,
    required this.senderId,
    this.senderUsername,
    this.senderFullName,
    required this.createdAt,
    this.delivered = true,
  });

  static int parseTimestamp(dynamic v) {
    if (v == null) return DateTime.now().millisecondsSinceEpoch;
    if (v is num) return v.toInt();
    final s = v.toString();
    final asInt = int.tryParse(s);
    if (asInt != null) {
      return asInt < 1e11 ? asInt * 1000 : asInt;
    }
    return DateTime.tryParse(s)?.millisecondsSinceEpoch ??
        DateTime.now().millisecondsSinceEpoch;
  }

  factory ChatMessage.fromJson(Map<String, dynamic> j) {
    final t = (j['type'] as String?) ?? 'text';
    final type = parseMessageType(t);
    final sender = j['sender'] as Map<String, dynamic>?;
    return ChatMessage(
      id: j['id'] as String,
      conversationId: j['conversationId'] as String,
      type: type,
      text: j['text'] as String?,
      media: j['media'] as String?,
      caption: j['caption'] as String?,
      senderId: j['senderId'] as String,
      senderUsername: (sender?['username'] ?? j['senderUsername']) as String?,
      senderFullName: (sender?['fullName'] ?? j['senderFullName']) as String?,
      createdAt: parseTimestamp(j['createdAt']),
      delivered: true,
    );
  }

  /// Local optimistic message before the server acks it.
  ChatMessage.local({
    required this.id,
    required this.conversationId,
    required this.type,
    this.text,
    this.media,
    this.caption,
    required this.senderId,
    required this.senderUsername,
    required this.senderFullName,
  })  : createdAt = DateTime.now().millisecondsSinceEpoch,
        delivered = false;

  /// Row shape for the local SQLite cache (client-side history only).
  Map<String, Object?> toMap() => {
        'id': id,
        'conversationId': conversationId,
        'type': type.name,
        'text': text,
        'media': media,
        'caption': caption,
        'senderId': senderId,
        'senderUsername': senderUsername,
        'senderFullName': senderFullName,
        'createdAt': createdAt,
        'delivered': delivered ? 1 : 0,
      };

  factory ChatMessage.fromMap(Map<String, Object?> m) {
    final t = (m['type'] as String?) ?? 'text';
    return ChatMessage(
      id: m['id'] as String,
      conversationId: m['conversationId'] as String,
      type: parseMessageType(t),
      text: m['text'] as String?,
      media: m['media'] as String?,
      caption: m['caption'] as String?,
      senderId: m['senderId'] as String,
      senderUsername: m['senderUsername'] as String?,
      senderFullName: m['senderFullName'] as String?,
      createdAt: (m['createdAt'] as num).toInt(),
      delivered: (m['delivered'] as int? ?? 1) == 1,
    );
  }

  /// Reconstruct a message from an FCM `data` payload (background/offline
  /// delivery). All FCM data values are strings, so empty strings map back to
  /// null for the optional text/media/caption fields. Used by [PushService] to
  /// persist messages that arrived via FCM into the local [MessageStore], so
  /// they survive an app restart instead of vanishing with the notification.
  factory ChatMessage.fromFcmData(Map<String, dynamic> d) {
    String? nonEmpty(String? s) => (s == null || s.isEmpty) ? null : s;
    final t = (d['type'] as String?) ?? 'text';
    final type = parseMessageType(t);
    final ts = int.tryParse((d['ts'] as String?) ?? '') ??
        DateTime.now().millisecondsSinceEpoch;
    return ChatMessage(
      id: (d['messageId'] as String?) ?? '${d['senderId']}-$ts',
      conversationId: d['conversationId'] as String,
      type: type,
      text: nonEmpty(d['text'] as String?),
      media: nonEmpty(d['media'] as String?),
      caption: nonEmpty(d['caption'] as String?),
      senderId: d['senderId'] as String? ?? '',
      senderUsername: nonEmpty(d['senderUsername'] as String?),
      senderFullName: nonEmpty(d['senderFullName'] as String?),
      createdAt: ts,
      delivered: true,
    );
  }
}