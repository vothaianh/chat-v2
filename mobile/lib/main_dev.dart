// Development entrypoint — points at the local backend.
// Run: flutter run --flavor dev -t lib/main_dev.dart
import 'config/app_config.dart';
import 'main.dart';

void main() => bootstrapApp(AppConfig.dev);
