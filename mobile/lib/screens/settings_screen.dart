import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../services/app_state.dart';
import '../services/config.dart';
import '../widgets/glass.dart';
import '../widgets/pulse.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Timer? _pingTimer;
  int? _pingMs;

  @override
  void initState() {
    super.initState();
    _measurePing();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _measurePing());
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    super.dispose();
  }

  Future<void> _measurePing() async {
    final sw = Stopwatch()..start();
    try {
      await http.get(Uri.parse(Config.baseUrl)).timeout(const Duration(seconds: 4));
      if (!mounted) return;
      setState(() => _pingMs = sw.elapsedMilliseconds);
    } catch (_) {
      if (!mounted) return;
      setState(() => _pingMs = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final username = app.auth.username ?? 'user';
    final topInset = MediaQuery.of(context).padding.top + 58;
    final pingLabel = _pingMs == null ? '—' : '$_pingMs ms';

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: const GlassAppBar(title: Text('you')),
      body: ListView(
        padding: EdgeInsets.only(top: topInset + 12, bottom: 180),
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
          _tile(icon: Icons.notifications_none_rounded, title: 'pings', trailing: pingLabel),
          _tile(icon: Icons.lock_outline_rounded, title: 'privacy'),
          _section('stack'),
          _tile(icon: Icons.dns_outlined, title: 'server', trailing: Config.isProd ? 'prod' : 'dev'),
          _tile(icon: Icons.info_outline_rounded, title: 'build', trailing: '1.0.0'),
          const SizedBox(height: 28),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Material(
              color: AppTheme.danger.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                onTap: () => app.logout(),
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 56,
                  child: Center(
                    child: Text('log out', style: AppTheme.body(size: 16, weight: FontWeight.w800, color: AppTheme.danger)),
                  ),
                ),
              ),
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
