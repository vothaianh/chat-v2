/// Central configuration. Change BASE_URL to point at your backend host.
/// For Android emulators use http://10.0.2.2:3000; for iOS sim/macOS use http://localhost:3000.
class Config {
  // Allow override via --dart-define=BASE_URL=...
  // Note: the iOS simulator shares the host's network, so http://localhost:3000 works.
  // For Android emulators use http://10.0.2.2:3000; for physical devices use the LAN IP.
  static const String baseUrl =
      String.fromEnvironment('BASE_URL', defaultValue: 'http://localhost:3000');

  static const String socketUrl = baseUrl;

  /// Static sticker set (asset references). Stickers are bundled, GIFs are URLs.
  static const List<String> stickers = [
    '😀', '😂', '🥰', '😎', '🤩', '😭', '😡', '👍', '🙏', '🔥',
    '🎉', '💯', '👀', '🤔', '😴', '🤯', '😱', '🙌', '💪', '✨',
  ];

  /// Trending GIF search terms (uses Giphy via a small public demo URL fallback).
  static const List<String> gifTerms = ['hello', 'thanks', 'wow', 'love', 'thumbs up', 'happy'];
}