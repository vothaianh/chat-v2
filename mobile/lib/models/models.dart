import 'dart:convert';

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
  final DateTime? lastSeenAt;

  ConversationMember({
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.username,
    this.fullName,
    this.avatarUrl,
    this.lastSeenAt,
  });

  factory ConversationMember.fromJson(Map<String, dynamic> j) => ConversationMember(
        userId: j['userId'] as String,
        role: j['role'] as String,
        joinedAt: DateTime.tryParse(j['joinedAt'].toString()) ?? DateTime.now(),
        username: j['username'] as String?,
        fullName: j['fullName'] as String?,
        avatarUrl: j['avatarUrl'] as String?,
        lastSeenAt: j['lastSeenAt'] != null ? DateTime.tryParse(j['lastSeenAt'].toString()) : null,
      );

  ConversationMember copyWith({String? avatarUrl, DateTime? lastSeenAt}) {
    return ConversationMember(
      userId: userId,
      role: role,
      joinedAt: joinedAt,
      username: username,
      fullName: fullName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
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

class MessageReaction {
  final String userId;
  final String emoji;

  const MessageReaction({required this.userId, required this.emoji});

  factory MessageReaction.fromJson(Map<String, dynamic> j) => MessageReaction(
        userId: j['userId'] as String,
        emoji: j['emoji'] as String,
      );

  Map<String, Object?> toJson() => {'userId': userId, 'emoji': emoji};

  static List<MessageReaction> listFrom(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => MessageReaction.fromJson(Map<String, dynamic>.from(e)))
        .where((r) => r.userId.isNotEmpty && r.emoji.isNotEmpty)
        .toList();
  }
}

class MessageReply {
  final String id;
  final MessageType type;
  final String? text;
  final String? media;
  final String senderId;
  final String? senderUsername;
  final String? senderFullName;

  const MessageReply({
    required this.id,
    required this.type,
    this.text,
    this.media,
    required this.senderId,
    this.senderUsername,
    this.senderFullName,
  });

  factory MessageReply.fromMessage(ChatMessage m) => MessageReply(
        id: m.id,
        type: m.type,
        text: m.text ?? m.caption,
        media: m.media,
        senderId: m.senderId,
        senderUsername: m.senderUsername,
        senderFullName: m.senderFullName,
      );

  factory MessageReply.fromJson(Map<String, dynamic> j) => MessageReply(
        id: j['id'] as String,
        type: parseMessageType(j['type'] as String?),
        text: j['text'] as String?,
        media: j['media'] as String?,
        senderId: j['senderId'] as String? ?? '',
        senderUsername: j['senderUsername'] as String?,
        senderFullName: j['senderFullName'] as String?,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type.name,
        'text': text,
        'media': media,
        'senderId': senderId,
        'senderUsername': senderUsername,
        'senderFullName': senderFullName,
      };

  String get preview {
    switch (type) {
      case MessageType.text:
        return text ?? '';
      case MessageType.sticker:
        return 'sticker';
      case MessageType.gif:
        return (text?.isNotEmpty ?? false) ? text! : 'gif';
      case MessageType.image:
        return (text?.isNotEmpty ?? false) ? text! : 'photo';
      case MessageType.call:
        return text ?? 'call';
    }
  }

  String get author =>
      (senderFullName?.isNotEmpty ?? false) ? senderFullName! : (senderUsername ?? 'someone');
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
  final List<MessageReaction> reactions;
  final MessageReply? replyTo;

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
    this.reactions = const [],
    this.replyTo,
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
      reactions: MessageReaction.listFrom(j['reactions']),
      replyTo: _parseReply(j['replyTo']),
    );
  }

  static MessageReply? _parseReply(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['id'] as String?;
    if (id == null || id.isEmpty) return null;
    return MessageReply.fromJson(Map<String, dynamic>.from(raw));
  }

  ChatMessage copyWith({
    bool? delivered,
    List<MessageReaction>? reactions,
    MessageReply? replyTo,
  }) {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      type: type,
      text: text,
      media: media,
      caption: caption,
      senderId: senderId,
      senderUsername: senderUsername,
      senderFullName: senderFullName,
      createdAt: createdAt,
      delivered: delivered ?? this.delivered,
      reactions: reactions ?? this.reactions,
      replyTo: replyTo ?? this.replyTo,
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
    this.replyTo,
  })  : createdAt = DateTime.now().millisecondsSinceEpoch,
        delivered = false,
        reactions = const [];

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
        'reactions': jsonEncode(reactions.map((r) => r.toJson()).toList()),
        'replyTo': replyTo == null ? null : jsonEncode(replyTo!.toJson()),
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
      reactions: MessageReaction.listFrom(_decodeReactions(m['reactions'])),
      replyTo: _parseStoredReply(m['replyTo']),
    );
  }

  static MessageReply? _parseStoredReply(Object? raw) {
    if (raw is Map) return _parseReply(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        return _parseReply(jsonDecode(raw));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static dynamic _decodeReactions(Object? raw) {
    if (raw is List) return raw;
    if (raw is String && raw.isNotEmpty) {
      try {
        return jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }
    return const [];
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