import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A frosted "liquid glass" surface: a backdrop blur behind a translucent fill
/// with a subtle top highlight and hairline border — the base for glass app bars,
/// tab bars, and pills used across the app.
class GlassSurface extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;
  final Border? border;
  final EdgeInsetsGeometry? padding;
  final Color? tint;

  const GlassSurface({
    super.key,
    required this.child,
    this.blur = 24,
    this.opacity = 0.6,
    this.borderRadius,
    this.border,
    this.padding,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.zero;
    final base = tint ?? AppTheme.surface;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: border,
            // Layered fill: translucent surface + faint white sheen for the
            // "liquid glass" light-catch on top.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                base.withValues(alpha: opacity + 0.08),
                base.withValues(alpha: opacity),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// One item in the [GlassBottomBar].
class GlassNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const GlassNavItem({required this.icon, required this.activeIcon, required this.label});
}

/// A frosted "liquid glass" bottom navigation bar. Floats over content
/// (use with `extendBody: true`) with a blurred fill and a pill highlight.
class GlassBottomBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<GlassNavItem> items;

  const GlassBottomBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return GlassSurface(
      blur: 30,
      opacity: 0.55,
      border: const Border(
        top: BorderSide(color: Color(0x1AFFFFFF), width: 0.6),
      ),
      child: Padding(
        padding: EdgeInsets.only(top: 8, bottom: 8 + bottomPad, left: 12, right: 12),
        child: Row(
          children: [
            for (int i = 0; i < items.length; i++)
              Expanded(child: _item(i)),
          ],
        ),
      ),
    );
  }

  Widget _item(int i) {
    final item = items[i];
    final selected = i == currentIndex;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: selected
              ? const LinearGradient(colors: [AppTheme.primary, AppTheme.primaryDark])
              : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? item.activeIcon : item.icon,
              size: 23,
              color: selected ? Colors.white : AppTheme.textSecondary,
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A glass app bar with an optional bottom (e.g. a TabBar). Content scrolls
/// underneath it, so use with `extendBodyBehindAppBar: true`.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;
  final List<Widget> actions;
  final Widget? leading;
  final PreferredSizeWidget? bottom;

  const GlassAppBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.leading,
    this.bottom,
  });

  static const double _barHeight = 56;

  // Status-bar inset read from the primary view (available without a context,
  // so preferredSize can include it and the reserved height matches the content).
  double get _topInset {
    final view = PlatformDispatcher.instance.views.first;
    return view.padding.top / view.devicePixelRatio;
  }

  @override
  Size get preferredSize => Size.fromHeight(
      _topInset + _barHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    return GlassSurface(
      blur: 30,
      opacity: 0.55,
      border: const Border(
        bottom: BorderSide(color: Color(0x1AFFFFFF), width: 0.6),
      ),
      child: Padding(
        padding: EdgeInsets.only(top: topPad),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: _barHeight,
              child: Row(
                children: [
                  if (leading != null)
                    leading!
                  else
                    const SizedBox(width: 20),
                  Expanded(
                    child: DefaultTextStyle.merge(
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                      child: title,
                    ),
                  ),
                  ...actions,
                  const SizedBox(width: 6),
                ],
              ),
            ),
            if (bottom != null) bottom!,
          ],
        ),
      ),
    );
  }
}
