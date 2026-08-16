import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
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
  bool _uploading = false;

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
    final avatarUrl = app.auth.avatarUrl;
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
                GestureDetector(
                  onTap: _uploading ? null : _changeAvatar,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      PulseAvatar(label: username, imageUrl: avatarUrl, size: 64, online: true),
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.surfaceElevated, width: 2),
                          ),
                          child: _uploading
                              ? const Padding(
                                  padding: EdgeInsets.all(5),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                    color: AppTheme.primaryInk,
                                  ),
                                )
                              : const Icon(Icons.photo_camera_rounded, size: 13, color: AppTheme.primaryInk),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('@$username', style: AppTheme.display(size: 22, letterSpacing: -0.6)),
                      const SizedBox(height: 4),
                      Text(
                        'tap photo to change',
                        style: AppTheme.body(size: 13, weight: FontWeight.w700, color: AppTheme.primary),
                      ),
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

  Future<void> _changeAvatar() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppTheme.surface,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textFaint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              _sheetTile(Icons.photo_camera_rounded, 'camera', () {
                Navigator.pop(ctx, ImageSource.camera);
              }),
              _sheetTile(Icons.photo_library_rounded, 'photo library', () {
                Navigator.pop(ctx, ImageSource.gallery);
              }),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    final picked = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1024,
      requestFullMetadata: false,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploading = true);
    final ok = await context.read<AppState>().updateAvatar(
          picked.path,
          contentType: picked.mimeType,
        );
    if (!mounted) return;
    setState(() => _uploading = false);
    if (!ok) {
      final err = context.read<AppState>().error ?? 'couldn’t update photo';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }

  Widget _sheetTile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppTheme.primary),
      ),
      title: Text(label, style: AppTheme.body(size: 15.5, weight: FontWeight.w700)),
      onTap: onTap,
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
