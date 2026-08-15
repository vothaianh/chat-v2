import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Deterministic squircle avatar from a name — lime / orchid / violet / aqua.
class PulseAvatar extends StatelessWidget {
  final String label;
  final double size;
  final bool online;
  final bool group;

  const PulseAvatar({
    super.key,
    required this.label,
    this.size = 52,
    this.online = false,
    this.group = false,
  });

  static const _palettes = [
    [Color(0xFFC6FF4A), Color(0xFF7CFF6B)],
    [Color(0xFFFF4D9A), Color(0xFFFF8A5B)],
    [Color(0xFFA78BFA), Color(0xFF60A5FA)],
    [Color(0xFF5CE1E6), Color(0xFFC6FF4A)],
    [Color(0xFFFFB020), Color(0xFFFF4D9A)],
  ];

  List<Color> get _colors {
    if (group) return const [AppTheme.violet, AppTheme.aqua];
    final h = label.toLowerCase().codeUnits.fold<int>(0, (a, b) => a + b);
    return _palettes[h % _palettes.length];
  }

  @override
  Widget build(BuildContext context) {
    final initial = label.trim().isNotEmpty ? label.trim()[0].toUpperCase() : '?';
    final radius = size * 0.34;
    final colors = _colors;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: AppTheme.display(
                size: size * 0.38,
                color: AppTheme.primaryInk,
                letterSpacing: -1,
              ),
            ),
          ),
          if (online)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * 0.28,
                height: size * 0.28,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.background, width: 2.2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ink canvas with two soft brand glows. Wrap any screen body.
class PulseBackdrop extends StatelessWidget {
  final Widget child;
  const PulseBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: AppTheme.background)),
        Positioned(
          top: -80,
          right: -60,
          child: _orb(220, AppTheme.primary.withValues(alpha: 0.10)),
        ),
        Positioned(
          bottom: 80,
          left: -80,
          child: _orb(260, AppTheme.accent.withValues(alpha: 0.08)),
        ),
        Positioned.fill(child: child),
      ],
    );
  }

  static Widget _orb(double size, Color color) {
    return IgnorePointer(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }
}

class PulseEmpty extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  const PulseEmpty({
    super.key,
    required this.title,
    required this.subtitle,
    this.icon = Icons.bolt_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: AppTheme.surfaceElevated,
                border: Border.all(color: AppTheme.divider),
              ),
              child: Icon(icon, size: 32, color: AppTheme.primary),
            ),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center, style: AppTheme.display(size: 22)),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTheme.body(size: 14, color: AppTheme.textSecondary, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

Route<T> pulseRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (_, __, ___) => page,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (_, anim, __, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.04, 0.02), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}
