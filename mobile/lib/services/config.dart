import '../config/app_config.dart';

/// Runtime configuration facade. The active environment (dev/prod) and its
/// endpoint come from [AppConfig], selected by the build flavor. See
/// `lib/config/app_config.dart` and the `main_dev.dart` / `main_prod.dart`
/// entrypoints.
class Config {
  static AppConfig _active = AppConfig.resolve();

  /// Set by the flavor entrypoint before the app runs.
  static void init(AppConfig config) => _active = config;

  static AppConfig get active => _active;

  static String get baseUrl => _active.baseUrl;
  static String get socketUrl => _active.baseUrl;
  static String get appName => _active.appName;
  static bool get isProd => _active.isProd;

  static const List<String> emojis = [
    '😀', '😂', '🥰', '😎', '🤩', '😭', '😡', '👍', '🙏', '🔥',
    '🎉', '💯', '👀', '🤔', '😴', '🤯', '😱', '🙌', '💪', '✨',
  ];

  static const _faces = ['hey', 'love', 'lol', 'wow', 'sad', 'cool'];

  static List<String> _pack(String id) => [
        for (final face in _faces) 'assets/stickers/$id/$face.jpg',
      ];

  static const List<({String id, String name, String cover, List<String> extra})> stickerSets = [
    (
      id: 'volt',
      name: 'volt',
      cover: 'assets/stickers/volt/hey.jpg',
      extra: [
        'assets/stickers/volt/fire.jpg',
        'assets/stickers/volt/angry.jpg',
        'assets/stickers/volt/yes.jpg',
        'assets/stickers/volt/thanks.jpg',
        'assets/stickers/volt/sleepy.jpg',
        'assets/stickers/volt/boom.jpg',
      ],
    ),
    (id: 'orchid', name: 'orchid', cover: 'assets/stickers/orchid/hey.jpg', extra: []),
    (id: 'aqua', name: 'aqua', cover: 'assets/stickers/aqua/hey.jpg', extra: []),
    (id: 'ghost', name: 'ghost', cover: 'assets/stickers/ghost/hey.jpg', extra: []),
    (id: 'cat', name: 'ink cat', cover: 'assets/stickers/cat/hey.jpg', extra: []),
    (id: 'star', name: 'star', cover: 'assets/stickers/star/hey.jpg', extra: []),
    (id: 'dumpling', name: 'dumpling', cover: 'assets/stickers/dumpling/hey.jpg', extra: []),
    (id: 'moon', name: 'moon', cover: 'assets/stickers/moon/hey.jpg', extra: []),
    (id: 'flame', name: 'flame', cover: 'assets/stickers/flame/hey.jpg', extra: []),
    (id: 'heart', name: 'heart', cover: 'assets/stickers/heart/hey.jpg', extra: []),
  ];

  static List<String> stickersFor(String setId) {
    final extra = stickerSets.where((s) => s.id == setId).map((s) => s.extra).firstOrNull ?? const [];
    return [..._pack(setId), ...extra];
  }

  /// Trending GIF search terms (uses Giphy via a small public demo URL fallback).
  static const List<String> gifTerms = ['hello', 'thanks', 'wow', 'love', 'thumbs up', 'happy'];
}
