import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../services/config.dart';
import '../widgets/glass.dart';
import '../widgets/pulse.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final username = app.auth.username ?? 'user';
    final topInset = MediaQuery.of(context).padding.top + 58;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('you')),
      body: ListView(
        padding: EdgeInsets.only(top: topInset + 12, bottom: 130),
        children: [
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 22),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: AppTheme.surfaceElevated,
              border: Border.all(color: AppTheme.divider),
            ),
            child: Row(
              children: [
                PulseAvatar(label: username, size: 64, online: true),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('@$username', style: AppTheme.display(size: 22, letterSpacing: -0.6)),
                      const SizedBox(height: 4),
                      Text('live now', style: AppTheme.body(size: 13, weight: FontWeight.w700, color: AppTheme.primary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _section('prefs'),
          _tile(icon: Icons.dark_mode_rounded, title: 'look', trailing: 'night'),
          _tile(icon: Icons.notifications_none_rounded, title: 'pings', trailing: 'on'),
          _tile(icon: Icons.lock_outline_rounded, title: 'privacy'),
          _section('stack'),
          _tile(icon: Icons.dns_outlined, title: 'server', trailing: Config.isProd ? 'prod' : 'dev'),
          _tile(icon: Icons.info_outline_rounded, title: 'build', trailing: '1.0.0'),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.danger,
                side: const BorderSide(color: AppTheme.danger),
                minimumSize: const Size.fromHeight(54),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              onPressed: () => app.logout(),
              child: Text('log out', style: AppTheme.body(size: 15, weight: FontWeight.w800, color: AppTheme.danger)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 8),
        child: Text(label, style: AppTheme.body(size: 12, weight: FontWeight.w800, color: AppTheme.textFaint)),
      );

  Widget _tile({required IconData icon, required String title, String? trailing}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 20, color: AppTheme.primary),
        ),
        title: Text(title, style: AppTheme.body(size: 15.5, weight: FontWeight.w700)),
        trailing: trailing == null
            ? const Icon(Icons.chevron_right_rounded, color: AppTheme.textFaint)
            : Text(trailing, style: AppTheme.body(size: 13.5, color: AppTheme.textSecondary, weight: FontWeight.w600)),
      ),
    );
  }
}
