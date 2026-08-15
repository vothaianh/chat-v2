import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

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
    this.blur = 28,
    this.opacity = 0.72,
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
            border: border ??
                Border.all(color: Colors.white.withValues(alpha: 0.08)),
            color: base.withValues(alpha: opacity),
          ),
          child: child,
        ),
      ),
    );
  }
}

class GlassNavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const GlassNavItem({required this.icon, required this.activeIcon, required this.label});
}

/// Floating island dock — lime pip on the active tab, no filled slab.
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
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 10 + bottomPad),
      child: GlassSurface(
        blur: 36,
        opacity: 0.78,
        borderRadius: BorderRadius.circular(28),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              for (int i = 0; i < items.length; i++)
                Expanded(child: _item(i)),
            ],
          ),
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
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected ? AppTheme.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                selected ? item.activeIcon : item.icon,
                size: 22,
                color: selected ? AppTheme.primaryInk : AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.label.toLowerCase(),
              style: AppTheme.body(
                size: 10.5,
                weight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? AppTheme.primary : AppTheme.textFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

  static const double _barHeight = 58;

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
      blur: 32,
      opacity: 0.55,
      borderRadius: BorderRadius.zero,
      border: const Border(
        bottom: BorderSide(color: Color(0x12FFFFFF), width: 0.6),
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
                  if (leading != null) leading! else const SizedBox(width: 20),
                  Expanded(
                    child: DefaultTextStyle.merge(
                      style: AppTheme.display(size: 26, letterSpacing: -1),
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
