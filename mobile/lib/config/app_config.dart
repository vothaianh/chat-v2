/// Build environment (Flutter flavor). Resolved at compile time from the
/// `FLAVOR` dart-define (set by the flutter `--flavor` / entrypoint), with an
/// optional `BASE_URL` override for ad-hoc testing.
enum Environment { dev, prod }

class AppConfig {
  final Environment env;
  final String baseUrl;
  final String appName;

  const AppConfig({
    required this.env,
    required this.baseUrl,
    required this.appName,
  });

  bool get isProd => env == Environment.prod;
  bool get isDev => env == Environment.dev;

  static const _devUrl = 'http://localhost:3010';
  static const _prodUrl = 'https://chat-api.truepilot.io';

  static const AppConfig dev = AppConfig(
    env: Environment.dev,
    baseUrl: _devUrl,
    appName: 'TruePilot Chat Dev',
  );

  static const AppConfig prod = AppConfig(
    env: Environment.prod,
    baseUrl: _prodUrl,
    appName: 'TruePilot Chat',
  );

  /// The active config. Chosen by the `FLAVOR` dart-define; `BASE_URL` (if set)
  /// overrides the endpoint for either flavor.
  static AppConfig resolve() {
    const flavor = String.fromEnvironment('FLAVOR', defaultValue: 'dev');
    const override = String.fromEnvironment('BASE_URL', defaultValue: '');
    final base = flavor == 'prod' ? prod : dev;
    if (override.isEmpty) return base;
    return AppConfig(env: base.env, baseUrl: override, appName: base.appName);
  }
}
