import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../theme/app_theme.dart';

/// Messenger-style strip of new camera-roll photos, ready to tap-send.
class RecentPhotoTray extends StatelessWidget {
  final List<AssetEntity> photos;
  final ValueChanged<AssetEntity> onSend;
  final VoidCallback onClose;
  final bool sending;

  const RecentPhotoTray({
    super.key,
    required this.photos,
    required this.onSend,
    required this.onClose,
    this.sending = false,
  });

  static Size _scaled(AssetEntity a) {
    final ow = (a.orientatedWidth > 0 ? a.orientatedWidth : a.width).toDouble();
    final oh = (a.orientatedHeight > 0 ? a.orientatedHeight : a.height).toDouble();
    if (ow <= 0 || oh <= 0) return const Size(72, 72);
    var w = ow * 0.10;
    var h = oh * 0.10;
    const maxLong = 132.0;
    final long = w > h ? w : h;
    if (long > maxLong) {
      final f = maxLong / long;
      w *= f;
      h *= f;
    }
    return Size(w, h);
  }

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) return const SizedBox.shrink();
    final shown = photos.take(1).toList();
    const extra = 0;
    final front = _scaled(shown.first);
    const tilt = 0.12;
    final stackW = front.width + 16;
    final stackH = front.height + 16;
    return Material(
      color: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          GestureDetector(
            onTap: onClose,
            child: Container(
              width: 26,
              height: 26,
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: AppTheme.surfaceElevated,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: const Icon(Icons.close_rounded, size: 15, color: AppTheme.textSecondary),
            ),
          ),
          SizedBox(
            width: stackW,
            height: stackH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: Center(
                    child: Transform.rotate(
                      angle: -tilt,
                      child: _cardWidget(shown.first, front: true, extra: extra),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cardWidget(AssetEntity asset, {required bool front, required int extra}) {
    final size = _scaled(asset);
    return GestureDetector(
      onTap: sending ? null : () => onSend(asset),
      child: Container(
        width: size.width,
        height: size.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: front ? 0.18 : 0.08), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: front ? 0.4 : 0.22),
              blurRadius: front ? 14 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _Thumb(asset: asset),
            if (front && extra > 0)
              Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  margin: const EdgeInsets.all(6),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.62),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '+$extra',
                    style: AppTheme.body(size: 11, weight: FontWeight.w800, color: Colors.white),
                  ),
                ),
              ),
            if (sending && front)
              const ColoredBox(
                color: Color(0x66000000),
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatefulWidget {
  final AssetEntity asset;
  const _Thumb({required this.asset});

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final w = widget.asset.orientatedWidth > 0 ? widget.asset.orientatedWidth : widget.asset.width;
    final h = widget.asset.orientatedHeight > 0 ? widget.asset.orientatedHeight : widget.asset.height;
    final data = await widget.asset.thumbnailDataWithSize(
      ThumbnailSize((w * 0.2).clamp(120, 400).round(), (h * 0.2).clamp(120, 400).round()),
    );
    if (!mounted) return;
    setState(() => _bytes = data);
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) {
      return const ColoredBox(color: AppTheme.surfaceHigh);
    }
    return Image.memory(_bytes!, fit: BoxFit.contain, gaplessPlayback: true);
  }
}
