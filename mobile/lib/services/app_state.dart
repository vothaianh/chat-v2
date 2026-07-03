import 'package:flutter/material.dart';
import '../models/models.dart';
import 'auth_service.dart';
import 'socket_service.dart';
import 'push_service.dart';
import 'message_store.dart';
import 'api_service.dart';

class AppState extends ChangeNotifier {
  final AuthService auth = AuthService();
  final SocketService socket = SocketService();
  final PushService push = PushService.instance;
  final MessageStore store = MessageStore();

  /// App-wide navigator key so [PushService] can push a [ChatScreen] when a
  /// notification is tapped (no BuildContext available there).
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  bool _bootstrapped = false;
  bool _loading = false;
  String? _error;
  List<Conversation> _conversations = [];

  // per-conversation ephemeral message logs (messages are NOT stored on the server)
  final Map<String, List<ChatMessage>> _messages = {};
  // online presence by userId
  final Map<String, bool> _online = {};
  // typing: conversationId -> userId -> bool
  final Map<String, Set<String>> _typingUsers = {};
  // the conversation currently open on screen (no banner for it)
  String? _activeConversationId;

  bool get bootstrapped => _bootstrapped;
  bool get loading => _loading;
  String? get error => _error;
  List<Conversation> get conversations => _conversations;
  bool get isAuthenticated => auth.isAuthenticated;
  String? get currentUserId => auth.userId;

  Future<void> bootstrap() async {
    try {
      await push.init();
      await auth.load();
      if (auth.isAuthenticated) {
        await _openStoreAndHydrate();
        _connectSocket();
        _wirePushPersist();
        await push.attach(auth.token!);
        await loadConversations();
      }
    } catch (e) {
      // Never let startup hang on the loading spinner — surface but continue.
      _error = e.toString();
    } finally {
      _bootstrapped = true;
      notifyListeners();
    }
  }

  void _connectSocket() {
    if (auth.token == null) return;
    socket.connect(auth.token!);
    socket.onMessage.listen(_onMessage);
    socket.onAck.listen(_onAck);
    socket.onTyping.listen(_onTyping);
    socket.onRead.listen(_onRead);
    socket.onPresence.listen(_onPresence);
  }

  /// Open the per-account local message DB and load cached history into memory
  /// so past conversations are visible immediately on reopen.
  Future<void> _openStoreAndHydrate() async {
    final acct = auth.userId;
    if (acct == null) return;
    try {
      await store.open(acct);
      _messages.clear();
      // Hydrate lazily per conversation on open; also warm the latest cache here.
      for (final entry in (await _loadAllHistory()).entries) {
        _messages[entry.key] = entry.value;
      }
    } catch (e) {
      _error = 'local history: $e';
    }
  }

  Future<Map<String, List<ChatMessage>>> _loadAllHistory() async {
    // Group everything by conversation once at startup.
    final latest = await store.latestPerConversation();
    final out = <String, List<ChatMessage>>{};
    for (final convId in latest.keys) {
      out[convId] = await store.loadConversation(convId);
    }
    return out;
  }

  /// Wire the FCM foreground-persist callback so messages that arrive via FCM
  /// while the app is open are merged into the live in-memory list and the
  /// local store (same path as socket-delivered messages). Idempotent.
  void _wirePushPersist() {
    push.onPersistMessage = (m) => _addMessage(m.conversationId, m);
  }

  /// Called on app resume: re-hydrate from the local store so messages that
  /// the FCM background isolate persisted while the app was backgrounded appear
  /// in the open chat. Reuses [MessageStore.loadConversation] per cached conv.
  Future<void> refreshFromStore() async {
    if (auth.userId == null) return;
    if (!store.isOpen) await store.open(auth.userId!);
    final convIds = <String>{};
    convIds.addAll(_messages.keys);
    convIds.addAll(_conversations.map((c) => c.id));
    for (final convId in convIds) {
      _messages[convId] = await store.loadConversation(convId);
    }
    notifyListeners();
  }

  // ---- auth ----
  Future<bool> register({
    required String username,
    required String fullName,
    required String email,
    required String password,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await auth.register(
        username: username,
        fullName: fullName,
        email: email,
        password: password,
      );
      await _openStoreAndHydrate();
      _connectSocket();
      _wirePushPersist();
      await push.attach(auth.token!);
      await loadConversations();
      _loading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _loading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> login({required String login, required String password}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await auth.login(login: login, password: password);
      await _openStoreAndHydrate();
      _connectSocket();
      _wirePushPersist();
      await push.attach(auth.token!);
      await loadConversations();
      _loading = false;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _error = e.message;
      _loading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = e.toString();
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    socket.disconnect();
    await push.detach();
    push.onPersistMessage = null;
    push.onTapConversation = null;
    // Keep the local history on disk so signing back in restores past chats;
    // just close the handle and clear the in-memory copy.
    await store.close();
    await auth.logout();
    _conversations = [];
    _messages.clear();
    _online.clear();
    _typingUsers.clear();
    notifyListeners();
  }

  // ---- conversations ----
  Future<void> loadConversations() async {
    if (auth.token == null) return;
    try {
      _conversations = await ApiService.listConversations(auth.token!);
      notifyListeners();
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
    }
  }

  /// Look up a cached conversation by id (null if not loaded).
  Conversation? _cachedConversation(String id) {
    for (final c in _conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Resolve a conversation by id, fetching the list from the server if it
  /// isn't cached (e.g. cold start). Returns null if it still can't be found.
  /// The UI layer uses this + [navigatorKey] to push a [ChatScreen] when a
  /// notification is tapped. Resolving (not navigating) lives here so the
  /// conversation list is refreshed server-side before opening.
  Future<Conversation?> resolveConversation(String conversationId) async {
    if (auth.token == null) return null;
    var conv = _cachedConversation(conversationId);
    if (conv == null) {
      await loadConversations();
      conv = _cachedConversation(conversationId);
    }
    if (conv == null) return null;
    // Hydrate this conversation's messages from the local store so the chat
    // isn't empty when opened from a notification tap — the background FCM
    // isolate persisted them to SQLite, but the in-memory map may not have
    // them yet (they only get pulled on resume otherwise).
    if (!store.isOpen) await store.open(auth.userId!);
    final loaded = await store.loadConversation(conversationId);
    _messages[conversationId] = loaded;
    debugPrint('[notif-tap] hydrated ${loaded.length} messages for $conversationId (storeOpen=${store.isOpen})');
    notifyListeners();
    return conv;
  }

  Future<Conversation?> startPrivateWith(String username) async {
    if (auth.token == null) return null;
    try {
      final user = await ApiService.getUser(auth.token!, username);
      final conv = await ApiService.createPrivate(auth.token!, user.id);
      _upsertConversation(conv);
      socket.joinConversation(conv.id);
      return conv;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return null;
    }
  }

  Future<Conversation?> startGroup(String title, List<String> usernames) async {
    if (auth.token == null) return null;
    try {
      final users = await Future.wait(
        usernames.map((u) => ApiService.getUser(auth.token!, u)),
      );
      final conv = await ApiService.createGroup(
        auth.token!,
        title: title,
        memberIds: users.map((u) => u.id).toList(),
      );
      _upsertConversation(conv);
      socket.joinConversation(conv.id);
      return conv;
    } on ApiException catch (e) {
      _error = e.message;
      notifyListeners();
      return null;
    }
  }

  void _upsertConversation(Conversation conv) {
    final idx = _conversations.indexWhere((c) => c.id == conv.id);
    if (idx >= 0) {
      _conversations[idx] = conv;
    } else {
      _conversations.insert(0, conv);
    }
    notifyListeners();
  }

  // ---- messages (ephemeral, client-only) ----
  List<ChatMessage> messagesFor(String conversationId) =>
      _messages[conversationId] ?? [];

  void sendText(String conversationId, String text) {
    final m = ChatMessage.local(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      conversationId: conversationId,
      type: MessageType.text,
      text: text,
      senderId: currentUserId ?? '',
      senderUsername: auth.username ?? '',
      senderFullName: auth.username ?? '',
    );
    _addMessage(conversationId, m);
    socket.sendMessage(m);
  }

  void sendSticker(String conversationId, String sticker) {
    final m = ChatMessage.local(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      conversationId: conversationId,
      type: MessageType.sticker,
      media: sticker,
      senderId: currentUserId ?? '',
      senderUsername: auth.username ?? '',
      senderFullName: auth.username ?? '',
    );
    _addMessage(conversationId, m);
    socket.sendMessage(m);
  }

  void sendGif(String conversationId, String gifUrl, {String? caption}) {
    final m = ChatMessage.local(
      id: '${DateTime.now().microsecondsSinceEpoch}',
      conversationId: conversationId,
      type: MessageType.gif,
      media: gifUrl,
      caption: caption,
      senderId: currentUserId ?? '',
      senderUsername: auth.username ?? '',
      senderFullName: auth.username ?? '',
    );
    _addMessage(conversationId, m);
    socket.sendMessage(m);
  }

  void _addMessage(String conversationId, ChatMessage m) {
    _messages.putIfAbsent(conversationId, () => []);
    // dedup by id (optimistic + server echo)
    if (_messages[conversationId]!.any((e) => e.id == m.id)) return;
    _messages[conversationId]!.add(m);
    // Persist to the local on-device history (fire-and-forget).
    store.upsert(m);
    notifyListeners();
  }

  /// Set by [ChatScreen] on open/close so we don't banner the chat you're in.
  void setActiveConversation(String? conversationId) {
    _activeConversationId = conversationId;
  }

  void _onMessage(ChatMessage m) {
    debugPrint('[socket] _onMessage from=${m.senderId} conv=${m.conversationId} text=${m.text} (me=${currentUserId}, activeConv=$_activeConversationId)');
    _addMessage(m.conversationId, m);
    // In-app banner for messages from others that aren't in the open chat.
    // (FCM handles offline recipients; online delivery arrives here instead.)
    if (m.senderId != currentUserId && m.conversationId != _activeConversationId) {
      push.showMessageNotification(
        title: (m.senderFullName?.isNotEmpty ?? false)
            ? m.senderFullName!
            : (m.senderUsername?.isNotEmpty ?? false ? m.senderUsername! : 'New message'),
        body: _messagePreview(m),
        conversationId: m.conversationId,
      );
    }
  }

  String _messagePreview(ChatMessage m) {
    switch (m.type) {
      case MessageType.text:
        return m.text ?? '';
      case MessageType.sticker:
        return m.media ?? '🙂';
      case MessageType.gif:
        return (m.caption?.isNotEmpty ?? false) ? m.caption! : 'GIF';
    }
  }

  void _onAck(Map<String, dynamic> ack) {
    final convId = ack['conversationId'] as String?;
    final id = ack['id'] as String?;
    if (convId == null || id == null) return;
    final list = _messages[convId];
    if (list == null) return;
    final i = list.indexWhere((e) => e.id == id);
    if (i >= 0) {
      list[i] = ChatMessage(
        id: list[i].id,
        conversationId: list[i].conversationId,
        type: list[i].type,
        text: list[i].text,
        media: list[i].media,
        caption: list[i].caption,
        senderId: list[i].senderId,
        senderUsername: list[i].senderUsername,
        senderFullName: list[i].senderFullName,
        createdAt: list[i].createdAt,
        delivered: true,
      );
      store.markDelivered(convId, id);
      notifyListeners();
    }
  }

  void sendTyping(String conversationId, bool isTyping) {
    socket.sendTyping(conversationId, isTyping);
  }

  void _onTyping(Map<String, dynamic> data) {
    final convId = data['conversationId'] as String?;
    final userId = data['userId'] as String?;
    final typing = data['isTyping'] as bool? ?? true;
    if (convId == null || userId == null || userId == currentUserId) return;
    _typingUsers.putIfAbsent(convId, () => {});
    if (typing) {
      _typingUsers[convId]!.add(userId);
    } else {
      _typingUsers[convId]!.remove(userId);
    }
    notifyListeners();
    if (typing) {
      Future.delayed(const Duration(seconds: 3), () {
        _typingUsers[convId]?.remove(userId);
        notifyListeners();
      });
    }
  }

  bool isTyping(String conversationId, String userId) {
    final set = _typingUsers[conversationId];
    return set != null && set.contains(userId);
  }

  List<String> typingUserIdsFor(String conversationId) {
    final set = _typingUsers[conversationId];
    return set == null ? const [] : set.toList();
  }

  void _onRead(Map<String, dynamic> data) {
    notifyListeners();
  }

  void _onPresence(Map<String, dynamic> data) {
    final userId = data['userId'] as String?;
    final online = data['online'] as bool?;
    if (userId == null || online == null) return;
    _online[userId] = online;
    notifyListeners();
  }

  bool isOnline(String userId) => _online[userId] ?? false;

  // ---- helpers for display ----
  String conversationTitle(Conversation c) {
    if (c.title != null && c.title!.isNotEmpty) return c.title!;
    if (c.type == ConversationType.private) {
      final other = c.members.where((m) => m.userId != currentUserId).toList();
      return other.isNotEmpty ? (other.first.fullName ?? other.first.username ?? 'User') : 'Chat';
    }
    final names = c.members.map((m) => m.fullName ?? m.username).whereType<String>().join(', ');
    return names.isEmpty ? 'Group' : names;
  }
}