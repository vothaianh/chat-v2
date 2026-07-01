import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../widgets/glass.dart';
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
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('Messages'),
        bottom: _GlassTabBar(controller: _tabs, counts: [all.length, direct.length, groups.length]),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NewChatScreen()),
        ),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('New chat'),
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
    // Content slides under the glass app bar; pad the top so the first row clears it.
    final topInset = MediaQuery.of(context).padding.top + 56 + 52;
    return RefreshIndicator(
      onRefresh: _refresh,
      child: convs.isEmpty
          ? _emptyState(topInset)
          : ListView.separated(
              padding: EdgeInsets.only(top: topInset, bottom: 96),
              itemCount: convs.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 84, color: AppTheme.divider),
              itemBuilder: (context, i) => _tile(context, convs[i], app),
            ),
    );
  }

  Widget _emptyState(double topInset) {
    return ListView(
      children: [
        SizedBox(height: topInset + 80),
        const Center(
          child: Column(
            children: [
              Icon(Icons.chat_bubble_outline_rounded, size: 64, color: AppTheme.textFaint),
              SizedBox(height: 16),
              Text('No conversations yet',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 16, fontWeight: FontWeight.w600)),
              SizedBox(height: 8),
              Text('Tap "New chat" to start messaging',
                  style: TextStyle(color: AppTheme.textFaint, fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, Conversation c, AppState app) {
    final title = app.conversationTitle(c);
    final subtitle = c.type == ConversationType.group
        ? '${c.members.length} members'
        : _otherUserSubtitle(c, app);
    final initial = title.isNotEmpty ? title.substring(0, 1).toUpperCase() : '?';
    final isGroup = c.type == ConversationType.group;
    final online = !isGroup && _isOtherOnline(c, app);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isGroup
                    ? [AppTheme.accent, const Color(0xFF0EA5B7)]
                    : [AppTheme.primary, AppTheme.primaryDark],
              ),
            ),
            alignment: Alignment.center,
            child: Text(initial,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20)),
          ),
          if (online)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  color: AppTheme.online,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.background, width: 2.5),
                ),
              ),
            ),
        ],
      ),
      title: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: online ? AppTheme.online : AppTheme.textSecondary, fontSize: 13.5)),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: AppTheme.textFaint),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatScreen(conversation: c)),
      ),
    );
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
    return online ? 'Online' : (u.username != null ? '@${u.username}' : '');
  }
}

/// Frosted tab bar with pill indicator + count badges, sits under the glass app bar.
class _GlassTabBar extends StatelessWidget implements PreferredSizeWidget {
  final TabController controller;
  final List<int> counts;
  const _GlassTabBar({required this.controller, required this.counts});

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    const labels = ['All', 'Direct', 'Groups'];
    return SizedBox(
      height: 52,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: TabBar(
          controller: controller,
          isScrollable: false,
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          labelPadding: EdgeInsets.zero,
          indicator: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [AppTheme.primary, AppTheme.primaryDark],
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primary.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          labelColor: Colors.white,
          unselectedLabelColor: AppTheme.textSecondary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13.5),
          splashBorderRadius: BorderRadius.circular(12),
          tabs: [
            for (int i = 0; i < labels.length; i++)
              Tab(
                height: 38,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(labels[i]),
                    if (counts[i] > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('${counts[i]}',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
        ),
      ),
    );
  }
}
