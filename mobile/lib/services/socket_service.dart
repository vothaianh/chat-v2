import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import '../models/models.dart';
import 'config.dart';

typedef Json = Map<String, dynamic>;

/// Socket.io real-time client. Handles connect/auth, message delivery,
/// presence, typing, read receipts, and @mentions.
class SocketService {
  io.Socket? _socket;
  bool _connected = false;

  final _messages = StreamController<ChatMessage>.broadcast();
  final _acks = StreamController<Map<String, dynamic>>.broadcast();
  final _typing = StreamController<Map<String, dynamic>>.broadcast();
  final _read = StreamController<Map<String, dynamic>>.broadcast();
  final _presence = StreamController<Map<String, dynamic>>.broadcast();
  final _mention = StreamController<Map<String, dynamic>>.broadcast();
  final _callEvents = StreamController<Map<String, dynamic>>.broadcast();
  final _reactions = StreamController<Map<String, dynamic>>.broadcast();
  final _connectionState = StreamController<bool>.broadcast();

  Stream<ChatMessage> get onMessage => _messages.stream;
  Stream<Map<String, dynamic>> get onAck => _acks.stream;
  Stream<Map<String, dynamic>> get onTyping => _typing.stream;
  Stream<Map<String, dynamic>> get onRead => _read.stream;
  Stream<Map<String, dynamic>> get onPresence => _presence.stream;
  Stream<Map<String, dynamic>> get onMention => _mention.stream;
  Stream<Map<String, dynamic>> get onCallEvent => _callEvents.stream;
  Stream<Map<String, dynamic>> get onReaction => _reactions.stream;
  Stream<bool> get onConnectionState => _connectionState.stream;

  bool get isConnected => _connected;

  void connect(String token, {String? userId}) {
    final prev = _socket;
    _socket = null;
    if (prev != null) {
      try {
        prev.dispose();
      } catch (_) {
        // Closing an already-closed engine socket throws; ignore.
      }
    }
    // forceNew: the socket.io manager is a singleton and otherwise reuses a
    // handshake that never got the JWT (websocket-only often drops `auth`).
    _socket = io.io(
      Config.socketUrl,
      io.OptionBuilder()
          .enableForceNew()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .setQuery({'token': token})
          .setExtraHeaders({'Authorization': 'Bearer $token'})
          .build(),
    );

    _socket!.onConnect((_) {
      debugPrint('[socket] connected to ${Config.socketUrl}');
      _connected = true;
      _connectionState.add(true);
    });
    _socket!.onDisconnect((_) {
      debugPrint('[socket] disconnected');
      _connected = false;
      _connectionState.add(false);
    });
    _socket!.onConnectError((e) {
      debugPrint('[socket] connect error: $e');
      _connected = false;
      _connectionState.add(false);
    });

    _socket!.on('message:new', (data) {
      debugPrint('[socket] message:new received: $data');
      _messages.add(ChatMessage.fromJson(data as Json));
    });
    _socket!.on('message:ack', (data) {
      _acks.add(data as Json);
    });
    _socket!.on('typing', (data) {
      _typing.add(data as Json);
    });
    _socket!.on('message:read', (data) {
      _read.add(data as Json);
    });
    _socket!.on('presence:update', (data) {
      _presence.add(data as Json);
    });
    _socket!.on('mention:new', (data) {
      _mention.add(data as Json);
    });
    _socket!.on('message:reaction', (data) {
      if (data is Map) _reactions.add(Map<String, dynamic>.from(data));
    });
    const callEvents = [
      'call:incoming',
      'call:ringing',
      'call:accepted',
      'call:busy',
      'call:ended',
      'call:offer',
      'call:answer',
      'call:ice',
    ];
    for (final ev in callEvents) {
      _socket!.on(ev, (data) {
        if (data is Map) {
          _callEvents.add({'event': ev, ...Map<String, dynamic>.from(data)});
        }
      });
    }

    _socket!.connect();
  }

  void sendMessage(ChatMessage m, {String? mediaKey}) {
    _socket?.emit('message:send', {
      'conversationId': m.conversationId,
      'type': m.type.name,
      'text': m.text,
      'media': mediaKey ?? m.media,
      'caption': m.caption,
      'clientId': m.id,
      if (m.replyTo != null) 'replyToId': m.replyTo!.id,
    });
  }

  void sendTyping(String conversationId, bool isTyping) {
    _socket?.emit('typing', {'conversationId': conversationId, 'isTyping': isTyping});
  }

  void markRead(String conversationId) {
    _socket?.emit('message:read', {'conversationId': conversationId});
  }

  void react(String conversationId, String messageId, String emoji) {
    _socket?.emit('message:react', {
      'conversationId': conversationId,
      'messageId': messageId,
      'emoji': emoji,
    });
  }

  void joinConversation(String conversationId) {
    _socket?.emit('conversation:join', {'conversationId': conversationId});
  }

  void emitCall(String event, Map<String, dynamic> payload) {
    _socket?.emit(event, payload);
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    _connected = false;
  }

  void dispose() {
    disconnect();
    _messages.close();
    _acks.close();
    _typing.close();
    _read.close();
    _presence.close();
    _mention.close();
    _callEvents.close();
    _reactions.close();
    _connectionState.close();
  }
}