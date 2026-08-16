import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../widgets/glass.dart';
import '../widgets/pulse.dart';
import 'chat_screen.dart';
import 'new_chat_screen.dart';

class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({super.key});

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AppState>().loadConversations();
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    await context.read<AppState>().loadConversations();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final all = app.conversations;
    final direct = all.where((c) => c.type == ConversationType.private).toList();
    final groups = all.where((c) => c.type == ConversationType.group).toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('inbox'),
        actions: [
          IconButton(
            onPressed: () => Navigator.of(context).push(pulseRoute(const NewChatScreen())),
            icon: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.add_rounded, color: AppTheme.primaryInk, size: 22),
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: _PulseTabs(controller: _tabs, counts: [all.length, direct.length, groups.length]),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _list(all, app),
          _list(direct, app),
          _list(groups, app),
        ],
      ),
    );
  }

  Widget _list(List<Conversation> convs, AppState app) {
    final topInset = MediaQuery.of(context).padding.top + 58 + 52;
    return RefreshIndicator(
      color: AppTheme.primaryInk,
      backgroundColor: AppTheme.primary,
      onRefresh: _refresh,
      child: convs.isEmpty
          ? ListView(
              padding: EdgeInsets.only(top: topInset),
              children: const [
                SizedBox(height: 80),
                PulseEmpty(
                  title: 'dead air.',
                  subtitle: 'nobody’s in your inbox yet. tap + and start something loud.',
                  icon: Icons.graphic_eq_rounded,
                ),
              ],
            )
          : ListView.builder(
              padding: EdgeInsets.only(top: topInset + 6, bottom: 120),
              itemCount: convs.length,
              itemBuilder: (context, i) => _tile(context, convs[i], app),
            ),
    );
  }

  Widget _tile(BuildContext context, Conversation c, AppState app) {
    final title = app.conversationTitle(c);
    final last = c.lastMessage ??
        (app.messagesFor(c.id).isNotEmpty ? app.messagesFor(c.id).last : null);
    final subtitle = last != null
        ? _preview(last, c, app)
        : (c.type == ConversationType.group
            ? '${c.members.length} in the mix'
            : _otherUserSubtitle(c, app));
    final isGroup = c.type == ConversationType.group;
    final online = !isGroup && _isOtherOnline(c, app);
    final unread = c.unreadCount;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: unread > 0 ? AppTheme.surfaceElevated : Colors.transparent,
        borderRadius: BorderRadius.circular(22),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => Navigator.of(context).push(pulseRoute(ChatScreen(conversation: c))),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            child: Row(
              children: [
                PulseAvatar(label: title, online: online, group: isGroup),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          size: 16,
                          weight: unread > 0 ? FontWeight.w800 : FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.body(
                          size: 13.5,
                          weight: unread > 0 ? FontWeight.w600 : FontWeight.w500,
                          color: unread > 0
                              ? AppTheme.textPrimary
                              : (last == null && online ? AppTheme.primary : AppTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (!isGroup || c.members.length == 2)
                  IconButton(
                    tooltip: 'voice call',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _startCall(context, app, c),
                    icon: const Icon(Icons.call_rounded, color: AppTheme.primary, size: 20),
                  ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (last != null)
                      Text(
                        _formatTime(last.createdAt),
                        style: AppTheme.body(
                          size: 11,
                          weight: FontWeight.w700,
                          color: unread > 0 ? AppTheme.primary : AppTheme.textFaint,
                        ),
                      ),
                    const SizedBox(height: 8),
                    if (unread > 0)
                      Container(
                        constraints: const BoxConstraints(minWidth: 22),
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          unread > 99 ? '99+' : '$unread',
                          textAlign: TextAlign.center,
                          style: AppTheme.body(
                            size: 11,
                            weight: FontWeight.w800,
                            color: AppTheme.primaryInk,
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 18),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startCall(BuildContext context, AppState app, Conversation c) async {
    final ok = await app.startCall(c, video: false);
    if (ok || !context.mounted) return;
    final err = app.calls.lastError ?? app.error ?? 'couldn’t start call';
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
  }

  bool _isOtherOnline(Conversation c, AppState app) {
    final other = c.members.where((m) => m.userId != app.currentUserId).toList();
    if (other.isEmpty) return false;
    return app.isOnline(other.first.userId);
  }

  String _otherUserSubtitle(Conversation c, AppState app) {
    final other = c.members.where((m) => m.userId != app.currentUserId).toList();
    if (other.isEmpty) return '';
    final u = other.first;
    final online = app.isOnline(u.userId);
    return online ? 'live now' : (u.username != null ? '@${u.username}' : '');
  }

  String _preview(ChatMessage m, Conversation c, AppState app) {
    final mine = m.senderId == app.currentUserId;
    final name = mine
        ? 'you'
        : ((m.senderFullName?.isNotEmpty ?? false)
            ? m.senderFullName!
            : (m.senderUsername != null ? '@${m.senderUsername}' : ''));
    final body = switch (m.type) {
      MessageType.text => m.text ?? '',
      MessageType.sticker => m.media ?? 'sticker',
      MessageType.gif => (m.caption?.isNotEmpty ?? false) ? m.caption! : 'gif',
      MessageType.image => (m.caption?.isNotEmpty ?? false) ? m.caption! : 'photo',
      MessageType.call => m.text ?? (m.media == 'video' ? 'video call' : 'voice call'),
    };
    if (c.type == ConversationType.group && name.isNotEmpty) return '$name  $body';
    return mine ? 'you  $body' : body;
  }

  String _formatTime(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return DateFormat.jm().format(d).toLowerCase();
    if (today.difference(day).inDays < 7) return DateFormat.E().format(d).toLowerCase();
    return DateFormat.MMMd().format(d).toLowerCase();
  }
}

class _PulseTabs extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;
  final List<int> counts;
  const _PulseTabs({required this.controller, required this.counts});

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    const labels = ['all', 'dms', 'groups'];
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(16),
          ),
          child: TabBar(
            controller: controller,
            isScrollable: false,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            labelPadding: EdgeInsets.zero,
            indicator: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              color: AppTheme.primary,
            ),
            labelColor: AppTheme.primaryInk,
            unselectedLabelColor: AppTheme.textSecondary,
            labelStyle: AppTheme.body(size: 13, weight: FontWeight.w800),
            unselectedLabelStyle: AppTheme.body(size: 13, weight: FontWeight.w600),
            splashBorderRadius: BorderRadius.circular(13),
            tabs: [
              for (int i = 0; i < labels.length; i++)
                Tab(
                  height: 36,
                  child: Text(counts[i] > 0 ? '${labels[i]}  ${counts[i]}' : labels[i]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
