import 'dart:async';
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
  final _connectionState = StreamController<bool>.broadcast();

  Stream<ChatMessage> get onMessage => _messages.stream;
  Stream<Map<String, dynamic>> get onAck => _acks.stream;
  Stream<Map<String, dynamic>> get onTyping => _typing.stream;
  Stream<Map<String, dynamic>> get onRead => _read.stream;
  Stream<Map<String, dynamic>> get onPresence => _presence.stream;
  Stream<Map<String, dynamic>> get onMention => _mention.stream;
  Stream<bool> get onConnectionState => _connectionState.stream;

  bool get isConnected => _connected;

  void connect(String token, {String? userId}) {
    if (_socket != null) {
      _socket!.dispose();
      _socket = null;
    }
    _socket = io.io(
      Config.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .build(),
    );

    _socket!.onConnect((_) {
      _connected = true;
      _connectionState.add(true);
    });
    _socket!.onDisconnect((_) {
      _connected = false;
      _connectionState.add(false);
    });
    _socket!.onConnectError((e) {
      _connected = false;
      _connectionState.add(false);
    });

    _socket!.on('message:new', (data) {
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

    _socket!.connect();
  }

  void sendMessage(ChatMessage m) {
    _socket?.emit('message:send', {
      'conversationId': m.conversationId,
      'type': m.type.name,
      'text': m.text,
      'media': m.media,
      'caption': m.caption,
      'clientId': m.id,
    });
  }

  void sendTyping(String conversationId, bool isTyping) {
    _socket?.emit('typing', {'conversationId': conversationId, 'isTyping': isTyping});
  }

  void markRead(String conversationId) {
    _socket?.emit('message:read', {'conversationId': conversationId});
  }

  void joinConversation(String conversationId) {
    _socket?.emit('conversation:join', {'conversationId': conversationId});
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
    _connectionState.close();
  }
}