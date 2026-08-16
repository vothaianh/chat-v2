import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/config.dart';

class MediaPicker extends StatefulWidget {
  final void Function(String emoji) onEmoji;
  final void Function(String stickerAsset) onSticker;
  final void Function(String gifUrl, {String? caption}) onGif;
  const MediaPicker({
    super.key,
    required this.onEmoji,
    required this.onSticker,
    required this.onGif,
  });

  @override
  State<MediaPicker> createState() => _MediaPickerState();
}

class _MediaPickerState extends State<MediaPicker> {
  String _setId = Config.stickerSets.first.id;

  static const List<String> _gifs = [
    'https://media.giphy.com/media/3o7TKsQ8gqVrxqMiAw/giphy.gif',
    'https://media.giphy.com/media/3oz8xQYbPIlWx7QGvS/giphy.gif',
    'https://media.giphy.com/media/26ufnwz3wDUli7AVu/giphy.gif',
    'https://media.giphy.com/media/l3q2K5EOAjM7WQYgw/giphy.gif',
    'https://media.giphy.com/media/3o7TKPdjp3OmZGO3O0/giphy.gif',
    'https://media.giphy.com/media/3oEjI6SIIHBdRxXI40/giphy.gif',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 380,
      child: DefaultTabController(
        length: 3,
        initialIndex: 1,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.textFaint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            TabBar(
              tabs: const [
                Tab(text: 'emoji'),
                Tab(text: 'sticker'),
                Tab(text: 'gifs'),
              ],
              labelColor: AppTheme.primaryInk,
              unselectedLabelColor: AppTheme.textSecondary,
              indicator: BoxDecoration(
                color: AppTheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelStyle: AppTheme.body(size: 13, weight: FontWeight.w800),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _emojiGrid(),
                  _stickerGrid(),
                  _gifGrid(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emojiGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: Config.emojis.length,
      itemBuilder: (_, i) {
        final s = Config.emojis[i];
        return InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => widget.onEmoji(s),
          child: Container(
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.surfaceElevated,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(s, style: const TextStyle(fontSize: 26)),
          ),
        );
      },
    );
  }

  Widget _stickerGrid() {
    final assets = Config.stickersFor(_setId);
    return Column(
      children: [
        SizedBox(
          height: 64,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
            itemCount: Config.stickerSets.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, i) {
              final set = Config.stickerSets[i];
              final on = set.id == _setId;
              return GestureDetector(
                onTap: () => setState(() => _setId = set.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 52,
                  decoration: BoxDecoration(
                    color: on ? AppTheme.primary : AppTheme.surfaceElevated,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: on ? AppTheme.primary : AppTheme.divider),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(set.cover, fit: BoxFit.cover),
                  ),
                ),
              );
            },
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
            ),
            itemCount: assets.length,
            itemBuilder: (_, i) {
              final asset = assets[i];
              return InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => widget.onSticker(asset),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: ColoredBox(
                    color: const Color(0xFF07070B),
                    child: Image.asset(asset, fit: BoxFit.cover),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _gifGrid() {
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.4,
      ),
      itemCount: _gifs.length,
      itemBuilder: (_, i) {
        final url = _gifs[i];
        return GestureDetector(
          onTap: () => widget.onGif(url),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: AppTheme.surfaceElevated,
                alignment: Alignment.center,
                child: const Icon(Icons.gif, size: 40, color: AppTheme.textSecondary),
              ),
            ),
          ),
        );
      },
    );
  }
}
