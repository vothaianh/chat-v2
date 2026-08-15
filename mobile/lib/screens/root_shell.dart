import 'package:flutter/material.dart';
import '../widgets/glass.dart';
import '../widgets/pulse.dart';
import 'conversations_screen.dart';
import 'contacts_screen.dart';
import 'settings_screen.dart';

class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 1;

  static const _items = [
    GlassNavItem(icon: Icons.people_outline_rounded, activeIcon: Icons.people_rounded, label: 'people'),
    GlassNavItem(icon: Icons.bolt_outlined, activeIcon: Icons.bolt_rounded, label: 'chats'),
    GlassNavItem(icon: Icons.person_outline_rounded, activeIcon: Icons.person_rounded, label: 'you'),
  ];

  @override
  Widget build(BuildContext context) {
    return PulseBackdrop(
      child: Scaffold(
        extendBody: true,
        backgroundColor: Colors.transparent,
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
      ),
    );
  }
}
