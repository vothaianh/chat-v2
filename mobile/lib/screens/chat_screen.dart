import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../widgets/message_bubble.dart';
import '../widgets/media_picker.dart';
import '../widgets/pulse.dart';
import '../widgets/glass.dart';

class ChatScreen extends StatefulWidget {
  final Conversation conversation;
  const ChatScreen({super.key, required this.conversation});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _isTyping = false;
  bool _uploading = false;
  Timer? _typingTimer;
  late final AppState _app;
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _app.socket.joinConversation(widget.conversation.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _app.setActiveConversation(widget.conversation.id);
      _app.markConversationRead(widget.conversation.id);
      _app.loadMessages(widget.conversation.id);
    });
  }

  @override
  void dispose() {
    _app.setActiveConversation(null);
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _typingTimer?.cancel();
    super.dispose();
  }

  void _onChanged(String v) {
    final app = context.read<AppState>();
    if (v.trim().isNotEmpty && !_isTyping) {
      _isTyping = true;
      app.sendTyping(widget.conversation.id, true);
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (_isTyping) {
        _isTyping = false;
        app.sendTyping(widget.conversation.id, false);
      }
    });
  }

  void _send() {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    context.read<AppState>().sendText(widget.conversation.id, text);
    _inputCtrl.clear();
    _scrollToLatest();
  }

  Widget _headerCallBtn({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppTheme.primary,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, color: AppTheme.primaryInk, size: 20),
          ),
        ),
      ),
    );
  }

  Future<void> _startCall({required bool video}) async {
    final app = context.read<AppState>();
    final ok = await app.startCall(widget.conversation, video: video);
    if (ok || !mounted) return;
    final err = app.calls.lastError ?? app.error ?? 'couldn’t start call';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  void _openAttach() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textFaint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              _attachTile(Icons.photo_camera_rounded, 'camera', () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              }),
              _attachTile(Icons.photo_library_rounded, 'photo library', () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              }),
              _attachTile(Icons.emoji_emotions_outlined, 'stickers & gifs', () {
                Navigator.pop(ctx);
                _openMediaPicker();
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachTile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppTheme.primary),
      ),
      title: Text(label, style: AppTheme.body(size: 15.5, weight: FontWeight.w700)),
      onTap: onTap,
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 2048,
      requestFullMetadata: false,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    final ok = await context.read<AppState>().sendImage(
          widget.conversation.id,
          picked.path,
          contentType: picked.mimeType,
        );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (ok) {
      _scrollToLatest();
    } else {
      final err = context.read<AppState>().error ?? 'couldn’t send photo';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  void _openMediaPicker() {
    final app = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (_) => MediaPicker(
        onSticker: (s) {
          app.sendSticker(widget.conversation.id, s);
          Navigator.pop(context);
          _scrollToLatest();
        },
        onGif: (url, {caption}) {
          app.sendGif(widget.conversation.id, url, caption: caption);
          Navigator.pop(context);
          _scrollToLatest();
        },
      ),
    );
  }

  /// List is `reverse: true`, so offset 0 is the latest message.
  void _scrollToLatest({bool instant = false}) {
    void jump() {
      if (!mounted || !_scrollCtrl.hasClients) return;
      if (instant) {
        _scrollCtrl.jumpTo(0);
      } else {
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      jump();
      // Images / date chips can grow the list after the first layout.
      WidgetsBinding.instance.addPostFrameCallback((_) => jump());
    });
  }

  bool get _pinnedToLatest =>
      !_scrollCtrl.hasClients || _scrollCtrl.position.pixels <= 80;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final messages = app.messagesFor(widget.conversation.id);
    final typingUserIds = app.typingUserIdsFor(widget.conversation.id);

    if (messages.length != _lastMessageCount) {
      final follow = _lastMessageCount == 0 || _pinnedToLatest;
      _lastMessageCount = messages.length;
      if (follow) _scrollToLatest(instant: true);
    }

    final title = app.conversationTitle(widget.conversation);
    final isGroup = widget.conversation.type == ConversationType.group;
    final canCall = widget.conversation.members.length == 2 || !isGroup;

    return PulseBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Row(
            children: [
              PulseAvatar(label: title, size: 36, group: isGroup, online: !isGroup && _isOtherOnline(app)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTheme.display(size: 17, letterSpacing: -0.4)),
                    if (typingUserIds.isNotEmpty)
                      Text('typing…', style: AppTheme.body(size: 11.5, weight: FontWeight.w700, color: AppTheme.primary))
                    else if (!isGroup)
                      _privatePresence(app)
                    else
                      Text('${widget.conversation.members.length} in the mix',
                          style: AppTheme.body(size: 11.5, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            if (canCall) ...[
              _headerCallBtn(
                icon: Icons.call_rounded,
                tooltip: 'voice call',
                onTap: () => _startCall(video: false),
              ),
              const SizedBox(width: 4),
              _headerCallBtn(
                icon: Icons.videocam_rounded,
                tooltip: 'video call',
                onTap: () => _startCall(video: true),
              ),
              const SizedBox(width: 10),
            ],
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: messages.isEmpty
                  ? Center(
                      child: app.isLoadingMessages(widget.conversation.id)
                          ? const CircularProgressIndicator()
                          : const PulseEmpty(
                              title: 'say something.',
                              subtitle: 'first message sets the vibe.',
                              icon: Icons.waving_hand_rounded,
                            ),
                    )
                  : ListView.builder(
                      controller: _scrollCtrl,
                      reverse: true,
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      itemCount: messages.length,
                      itemBuilder: (context, i) {
                        final index = messages.length - 1 - i;
                        final m = messages[index];
                        final isMine = m.senderId == app.currentUserId;
                        final prev = index > 0 ? messages[index - 1] : null;
                        final isCall = m.type == MessageType.call;
                        final showSender = !isCall && !isMine && (prev == null || prev.senderId != m.senderId);
                        final showDate = prev == null || !_sameDay(prev.createdAt, m.createdAt);
                        return Column(
                          children: [
                            if (showDate) _dateChip(m.createdAt),
                            MessageBubble(
                              message: m,
                              isMine: isMine,
                              showSender: showSender,
                              senderLabel: (m.senderFullName != null && m.senderFullName!.isNotEmpty)
                                  ? m.senderFullName
                                  : (m.senderUsername != null ? '@${m.senderUsername}' : null),
                              onCallTap: isCall ? () => _startCall(video: m.media == 'video') : null,
                            ),
                          ],
                        );
                      },
                    ),
            ),
            if (typingUserIds.isNotEmpty) _typingBar(typingUserIds, app),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  bool _sameDay(int a, int b) {
    final da = DateTime.fromMillisecondsSinceEpoch(a);
    final db = DateTime.fromMillisecondsSinceEpoch(b);
    return da.year == db.year && da.month == db.month && da.day == db.day;
  }

  Widget _dateChip(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final label = day == today
        ? 'today'
        : today.difference(day).inDays == 1
            ? 'yesterday'
            : '${d.day} ${_month(d.month)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: AppTheme.body(size: 11, weight: FontWeight.w700, color: AppTheme.textSecondary)),
      ),
    );
  }

  String _month(int m) {
    const names = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];
    return names[m - 1];
  }

  bool _isOtherOnline(AppState app) {
    final other = widget.conversation.members.where((m) => m.userId != app.currentUserId).toList();
    return other.isNotEmpty && app.isOnline(other.first.userId);
  }

  Widget _privatePresence(AppState app) {
    final online = _isOtherOnline(app);
    return Text(
      online ? 'live now' : 'offline',
      style: AppTheme.body(size: 11.5, weight: FontWeight.w700, color: online ? AppTheme.primary : AppTheme.textFaint),
    );
  }

  Widget _typingBar(List<String> userIds, AppState app) {
    final names = userIds.map((id) {
      final m = widget.conversation.members.where((x) => x.userId == id).firstWhere(
        (_) => true,
        orElse: () => ConversationMember(userId: id, role: '', joinedAt: DateTime.now(), username: 'someone'),
      );
      return m.fullName ?? m.username ?? 'someone';
    }).join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
      child: Text(
        '$names is cooking a reply…',
        style: AppTheme.body(size: 12.5, weight: FontWeight.w600, color: AppTheme.primary),
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            GestureDetector(
              onTap: _uploading ? null : _openAttach,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.divider),
                ),
                child: _uploading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add_rounded, color: AppTheme.primary),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GlassSurface(
                blur: 20,
                opacity: 0.8,
                borderRadius: BorderRadius.circular(22),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: TextField(
                  controller: _inputCtrl,
                  onChanged: _onChanged,
                  minLines: 1,
                  maxLines: 5,
                  textCapitalization: TextCapitalization.sentences,
                  style: AppTheme.body(size: 15.5),
                  decoration: InputDecoration(
                    hintText: 'say it',
                    isDense: true,
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _send,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.arrow_upward_rounded, color: AppTheme.primaryInk),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
