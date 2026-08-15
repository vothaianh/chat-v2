import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/config.dart';

class MediaPicker extends StatelessWidget {
  final void Function(String sticker) onSticker;
  final void Function(String gifUrl, {String? caption}) onGif;
  const MediaPicker({super.key, required this.onSticker, required this.onGif});

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
      height: 320,
      child: DefaultTabController(
        length: 2,
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
              tabs: const [Tab(text: 'stickers'), Tab(text: 'gifs')],
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
                  GridView.builder(
                    padding: const EdgeInsets.all(14),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 5,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                    ),
                    itemCount: Config.stickers.length,
                    itemBuilder: (_, i) {
                      final s = Config.stickers[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => onSticker(s),
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
                  ),
                  GridView.builder(
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
                        onTap: () => onGif(url),
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
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
