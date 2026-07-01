import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/glass.dart';
import 'conversations_screen.dart';
import 'contacts_screen.dart';
import 'settings_screen.dart';

/// Root navigation shell: Contacts / Chats / Settings behind a glass bottom bar.
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 1; // default to Chats

  static const _items = [
    GlassNavItem(icon: Icons.people_outline_rounded, activeIcon: Icons.people_rounded, label: 'Contacts'),
    GlassNavItem(icon: Icons.chat_bubble_outline_rounded, activeIcon: Icons.chat_bubble_rounded, label: 'Chats'),
    GlassNavItem(icon: Icons.settings_outlined, activeIcon: Icons.settings_rounded, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      backgroundColor: AppTheme.background,
      body: IndexedStack(
        index: _index,
        children: const [
          ContactsScreen(),
          ConversationsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: GlassBottomBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: _items,
      ),
    );
  }
}
