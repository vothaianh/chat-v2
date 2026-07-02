import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../widgets/message_bubble.dart';
import '../widgets/media_picker.dart';

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
  Timer? _typingTimer;
  late final AppState _app;

  @override
  void initState() {
    super.initState();
    _app = context.read<AppState>();
    _app.socket.joinConversation(widget.conversation.id);
    _app.socket.markRead(widget.conversation.id);
    _app.setActiveConversation(widget.conversation.id);
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
    _scrollToBottom();
  }

  void _openMediaPicker() {
    final app = context.read<AppState>();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => MediaPicker(
        onSticker: (s) {
          app.sendSticker(widget.conversation.id, s);
          Navigator.pop(context);
          _scrollToBottom();
        },
        onGif: (url, {caption}) {
          app.sendGif(widget.conversation.id, url, caption: caption);
          Navigator.pop(context);
          _scrollToBottom();
        },
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final messages = app.messagesFor(widget.conversation.id);
    final typingUserIds = app.typingUserIdsFor(widget.conversation.id);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            _avatar(app),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.conversationTitle(widget.conversation),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  if (typingUserIds.isNotEmpty)
                    Text(
                      'typing…',
                      style: const TextStyle(color: AppTheme.accent, fontSize: 12),
                    )
                  else if (widget.conversation.type == ConversationType.private)
                    _privatePresence(app)
                  else
                    Text(
                      '${widget.conversation.members.length} members',
                      style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const Center(child: Text('Say hi 👋', style: TextStyle(color: AppTheme.textSecondary)))
                : ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, i) {
                      final m = messages[i];
                      final isMine = m.senderId == app.currentUserId;
                      final prev = i > 0 ? messages[i - 1] : null;
                      final showSender = !isMine &&
                          (prev == null || prev.senderId != m.senderId);
                      return MessageBubble(
                        message: m,
                        isMine: isMine,
                        showSender: showSender,
                        senderLabel: m.senderUsername != null ? '@${m.senderUsername}' : null,
                      );
                    },
                  ),
          ),
          if (typingUserIds.isNotEmpty) _typingBar(typingUserIds, app),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _avatar(AppState app) {
    final title = app.conversationTitle(widget.conversation);
    final initial = title.isNotEmpty ? title.substring(0, 1).toUpperCase() : '?';
    return CircleAvatar(
      radius: 18,
      backgroundColor: widget.conversation.type == ConversationType.group ? AppTheme.accent : AppTheme.primary,
      child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
    );
  }

  Widget _privatePresence(AppState app) {
    final other = widget.conversation.members
        .where((m) => m.userId != app.currentUserId)
        .toList();
    if (other.isEmpty) return const SizedBox.shrink();
    final online = app.isOnline(other.first.userId);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: online ? AppTheme.online : AppTheme.offline,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          online ? 'Online' : 'Offline',
          style: TextStyle(color: online ? AppTheme.online : AppTheme.textSecondary, fontSize: 12),
        ),
      ],
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppTheme.surface,
      child: Row(
        children: [
          const SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent),
          ),
          const SizedBox(width: 8),
          Text('$names is typing…', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5)),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: AppTheme.divider)),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.emoji_emotions_outlined, color: AppTheme.primary),
              onPressed: _openMediaPicker,
            ),
            Expanded(
              child: TextField(
                controller: _inputCtrl,
                onChanged: _onChanged,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: '',
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send, color: AppTheme.primary),
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }
}