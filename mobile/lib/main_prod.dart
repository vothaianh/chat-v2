// Production entrypoint — points at https://chat-api.truepilot.io.
// Build: flutter build ipa --flavor prod -t lib/main_prod.dart
import 'config/app_config.dart';
import 'main.dart';

void main() => bootstrapApp(AppConfig.prod);
