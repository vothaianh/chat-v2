import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../widgets/glass.dart';
import 'chat_screen.dart';

/// Contacts: search a username to start a chat, and quick-access the people you
/// already talk to (derived from existing private conversations).
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
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatScreen(conversation: conv)),
      );
    } else if (app.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(app.error!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final contacts = _deriveContacts(app);
    final topInset = MediaQuery.of(context).padding.top + 56;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('Contacts')),
      body: ListView(
        padding: EdgeInsets.only(top: topInset + 12, bottom: 120),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: _startChat,
              decoration: InputDecoration(
                hintText: 'Find someone by @username',
                prefixIcon: const Icon(Icons.alternate_email_rounded, size: 20),
                suffixIcon: _busy
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      )
                    : IconButton(
                        icon: const Icon(Icons.arrow_forward_rounded),
                        onPressed: () => _startChat(_searchCtrl.text.trim()),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (contacts.isNotEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Recent',
                  style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3)),
            ),
          if (contacts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 80),
              child: Center(
                child: Column(
                  children: const [
                    Icon(Icons.person_search_rounded, size: 60, color: AppTheme.textFaint),
                    SizedBox(height: 14),
                    Text('No contacts yet',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 15, fontWeight: FontWeight.w600)),
                    SizedBox(height: 6),
                    Text('Search a username above to start chatting',
                        style: TextStyle(color: AppTheme.textFaint, fontSize: 13)),
                  ],
                ),
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
    final initial = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';
    final online = app.isOnline(m.userId);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(
        children: [
          Container(
            width: 48, height: 48,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [AppTheme.primary, AppTheme.primaryDark],
              ),
            ),
            alignment: Alignment.center,
            child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 18)),
          ),
          if (online)
            Positioned(
              right: 0, bottom: 0,
              child: Container(
                width: 14, height: 14,
                decoration: BoxDecoration(
                  color: AppTheme.online, shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.background, width: 2.5),
                ),
              ),
            ),
        ],
      ),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
      subtitle: Text(m.username != null ? '@${m.username}' : '',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
      trailing: IconButton(
        icon: const Icon(Icons.chat_bubble_outline_rounded, color: AppTheme.primary, size: 22),
        onPressed: () => m.username != null ? _startChat(m.username!) : null,
      ),
      onTap: () => m.username != null ? _startChat(m.username!) : null,
    );
  }

  /// Unique other-party members from existing private conversations.
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
