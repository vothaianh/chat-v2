# Chat — Flutter + NestJS instant messaging

1. When update backend, need to run docker compose up -d again

See `README.md` for full setup. Key constraints for anyone working in this repo:

- **Messages are never persisted.** The DB holds only users, device tokens, conversations, and members.
  Do not add a `message` table or write message bodies to the DB — that violates the core spec.
  Delivery is in-memory over Socket.io; offline recipients get FCM.
- **Backend** is in `backend/` (NestJS). Run via `docker compose up -d --build` from the repo root.
  Postgres host port is `5433` (to avoid clashing with a local 5432). The backend connects to
  `postgres:5432` inside the compose network.
- **Realtime auth:** the gateway authenticates the JWT from `socket.handshake.auth.token` directly
  (using `jsonwebtoken` + `ConfigService`), NOT via `@nestjs/jwt`'s `JwtService` — a separate JwtModule
  registration silently had no secret. Don't reintroduce that.
- **Global JWT guard** (`APP_GUARD` = `GlobalJwtGuard`) protects all REST routes; `@Public()` opts out
  (used on `auth/register`, `auth/login`).
- **FCM is graceful:** `FcmPushService` logs `[push:stub]` when no `FIREBASE_CREDENTIALS_BASE64` is set.
  Never make Firebase required for boot.
- **Flutter app** is in `mobile/`. Backend URL is `Config.baseUrl` (`mobile/lib/services/config.dart`),
  overridable via `--dart-define=BASE_URL=...`. Use `http://10.0.2.2:3000` for Android emulators.
- **e2e tests** (`backend/e2e-test.js`, `backend/e2e-group.js`) run with `node` and need
  `socket.io-client` (a devDependency). They register users, open sockets, and assert live delivery +
  no-persistence. Run them after `docker compose up`.

- **FCM push is wired on the mobile side** (`mobile/lib/services/push_service.dart`): `firebase_core`
  + `firebase_messaging` + `flutter_local_notifications`. On login it gets the FCM token and registers
  it with the backend (`/api/devices/register`); on logout it unregisters. Foreground messages become
  local notifications. App id is `com.truepilot.chat` (Android `applicationId`/namespace + iOS bundle
  id, plus the Kotlin package `com/truepilot/chat/MainActivity.kt`). Firebase config files live at
  `mobile/android/app/google-services.json` and `mobile/ios/Runner/GoogleService-Info.plist` and are
  git-ignored; templates are `mobile/google-services.example.json` /
  `mobile/GoogleService-Info.example.plist`.
- **Native build requirements (don't lower them):** Android minSdk 23 (FCM) + core library desugaring
  enabled (`isCoreLibraryDesugaringEnabled` + `desugar_jdk_libs:2.1.4`) — flutter_local_notifications
  requires desugaring or `checkDebugAarMetadata` fails. The `com.google.gms.google-services` Gradle
  plugin (v4.4.2) is applied in `android/settings.gradle.kts` and `app/build.gradle.kts`. iOS
  deployment target is 15.0 (Firebase requires it; uses Swift Package Manager, no Podfile).

Flutter analyze currently has only `info`-level lint nits (no errors/warnings). Keep it that way.
`build/**` and `ios/Pods/**` are excluded from analysis (the firebase_messaging Swift Package Manager
source packages under `build/ios/SourcePackages` otherwise trip the analyzer with test-file errors).