import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../services/config.dart';
import '../widgets/glass.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final username = app.auth.username ?? 'user';
    final initial = username.isNotEmpty ? username.substring(0, 1).toUpperCase() : '?';
    final topInset = MediaQuery.of(context).padding.top + 56;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('Settings')),
      body: ListView(
        padding: EdgeInsets.only(top: topInset + 12, bottom: 120),
        children: [
          // Profile card
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [AppTheme.surfaceElevated, AppTheme.surface],
              ),
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                Container(
                  width: 62, height: 62,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                      colors: [AppTheme.primary, AppTheme.primaryDark],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(initial, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 26)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('@$username',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 8, height: 8,
                            decoration: const BoxDecoration(color: AppTheme.online, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 6),
                          const Text('Online',
                              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          _section('Preferences'),
          _tile(icon: Icons.dark_mode_rounded, title: 'Appearance', trailing: 'Dark', onTap: () {}),
          _tile(icon: Icons.notifications_outlined, title: 'Notifications', trailing: 'On', onTap: () {}),
          _tile(icon: Icons.lock_outline_rounded, title: 'Privacy', onTap: () {}),

          _section('About'),
          _tile(icon: Icons.dns_outlined, title: 'Server', trailing: _host(), onTap: () {}),
          _tile(icon: Icons.info_outline_rounded, title: 'Version', trailing: '1.0.0', onTap: () {}),

          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.danger,
                side: const BorderSide(color: AppTheme.danger),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              onPressed: () => app.logout(),
            ),
          ),
        ],
      ),
    );
  }

  static String _host() {
    final u = Uri.tryParse(Config.baseUrl);
    return u?.host ?? Config.baseUrl;
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Text(label.toUpperCase(),
            style: const TextStyle(
                color: AppTheme.textFaint, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.6)),
      );

  Widget _tile({required IconData icon, required String title, String? trailing, VoidCallback? onTap}) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: AppTheme.surfaceElevated,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: AppTheme.textSecondary),
      ),
      title: Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null)
            Text(trailing, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: AppTheme.textFaint),
        ],
      ),
    );
  }
}
