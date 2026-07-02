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

  /// Static sticker set (asset references). Stickers are bundled, GIFs are URLs.
  static const List<String> stickers = [
    '😀', '😂', '🥰', '😎', '🤩', '😭', '😡', '👍', '🙏', '🔥',
    '🎉', '💯', '👀', '🤔', '😴', '🤯', '😱', '🙌', '💪', '✨',
  ];

  /// Trending GIF search terms (uses Giphy via a small public demo URL fallback).
  static const List<String> gifTerms = ['hello', 'thanks', 'wow', 'love', 'thumbs up', 'happy'];
}
