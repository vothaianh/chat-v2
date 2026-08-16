import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../widgets/glass.dart';
import '../widgets/pulse.dart';
import 'chat_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final _searchCtrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _startChat(String username) async {
    if (username.isEmpty) return;
    setState(() => _busy = true);
    final app = context.read<AppState>();
    final conv = await app.startPrivateWith(username.toLowerCase());
    if (!mounted) return;
    setState(() => _busy = false);
    if (conv != null) {
      Navigator.of(context).push(pulseRoute(ChatScreen(conversation: conv)));
    } else if (app.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(app.error!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final contacts = _deriveContacts(app);
    final topInset = MediaQuery.of(context).padding.top + 58;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('people')),
      body: ListView(
        padding: EdgeInsets.only(top: topInset + 12, bottom: 130),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: _startChat,
              decoration: InputDecoration(
                hintText: 'find @username',
                prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20, color: AppTheme.primary),
                suffixIcon: _busy
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        icon: const Icon(Icons.arrow_forward_rounded, color: AppTheme.primary),
                        onPressed: () => _startChat(_searchCtrl.text.trim()),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          if (contacts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: Text('recent', style: AppTheme.body(size: 12, weight: FontWeight.w800, color: AppTheme.textFaint)),
            ),
          if (contacts.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 72),
              child: PulseEmpty(
                title: 'ghost town.',
                subtitle: 'search a username and slide in.',
                icon: Icons.person_search_rounded,
              ),
            )
          else
            ...contacts.map((c) => _contactTile(app, c)),
        ],
      ),
    );
  }

  Widget _contactTile(AppState app, ConversationMember m) {
    final name = m.fullName ?? m.username ?? 'User';
    final online = app.isOnline(m.userId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        leading: PulseAvatar(label: name, imageUrl: m.avatarUrl, size: 48, online: online),
        title: Text(name, style: AppTheme.body(size: 15.5, weight: FontWeight.w700)),
        subtitle: Text(
          m.username != null ? '@${m.username}' : '',
          style: AppTheme.body(size: 13, color: AppTheme.textSecondary),
        ),
        trailing: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.bolt_rounded, color: AppTheme.primary, size: 20),
        ),
        onTap: () => m.username != null ? _startChat(m.username!) : null,
      ),
    );
  }

  List<ConversationMember> _deriveContacts(AppState app) {
    final seen = <String>{};
    final out = <ConversationMember>[];
    for (final c in app.conversations) {
      if (c.type != ConversationType.private) continue;
      for (final m in c.members) {
        if (m.userId == app.currentUserId) continue;
        if (seen.add(m.userId)) out.add(m);
      }
    }
    return out;
  }
}
