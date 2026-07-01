# Instant Messaging App (Flutter + NestJS)

A professional instant-messaging system per `product_specs.md`:

- **Frontend:** Flutter (latest stable)
- **Backend:** NestJS (latest) + Postgres 17 with the `uuid-ossp` extension, fully Dockerized
- **Messages are NOT stored** — delivered instantly over **Socket.io**, then discarded
- Durable data only: **Users**, **Device Tokens (FCM)**, **Conversations + Members**
- Private chat & group chat
- Register by **username + full name + email**
- **Tag people by username** (`@vothaianh`) — mentions resolve and notify
- **Stickers & GIF** messages
- **FCM push** to offline recipients (graceful no-op when Firebase isn't configured)
- Latency-focused delivery: in-memory room routing, no DB writes on the hot path

## Monorepo layout

```
chat/
├── docker-compose.yml          # postgres + backend (all backend services dockerized)
├── chat-backend.env.example     # copy to backend/.env for local runs
├── backend/                     # NestJS API + Socket.io gateway
│   ├── Dockerfile
│   ├── db/0001-init.sql         # uuid extension + canonical schema
│   ├── e2e-test.js              # runnable end-to-end realtime test (node)
│   ├── e2e-group.js             # group + offline-push test (node)
│   └── src/
│       ├── auth/                # register/login/JWT, global guard, @Public()
│       ├── users/               # User entity, username lookup, mention resolution
│       ├── device-tokens/       # FCM token storage (multi-device per user)
│       ├── conversations/       # private + group conversations, members
│       ├── realtime/            # Socket.io gateway: delivery, presence, mentions
│       ├── push/                # PushService interface + FCM impl (graceful stub)
│       └── config/               # env-driven configuration
└── mobile/                      # Flutter app
    └── lib/
        ├── main.dart
        ├── theme/app_theme.dart
        ├── models/models.dart
        ├── services/             # api, socket, auth, app_state, config
        ├── widgets/              # message_bubble, media_picker (stickers/GIF)
        └── screens/              # auth, conversations, chat, new_chat
```

## Architecture (the key decision: ephemeral messages)

The spec says **do not store messages**. So the database holds only what's needed for routing
and identity — never a message body:

- **Hot path (message send):** `client → Socket.io → gateway.onMessage() → server.to(room).emit('message:new')`
  The envelope exists only in memory for the duration of the emit, then is gone. No DB write.
- **Offline recipients:** the gateway computes offline member ids, fetches their FCM device tokens,
  and calls `PushService.send()`. If Firebase is configured, real FCM notifications go out; if not,
  the service logs `[push:stub]` so the flow is observable without credentials.
- **Presence:** an in-memory `PresenceService` maps `userId → Set<socketId>`. Online members get
  live delivery; offline members get FCM. Last-seen is the only thing persisted (on connect/disconnect).
- **@mentions:** the gateway regex-extracts `@username` from message text, resolves them to user ids
  via `UsersService`, and emits a `mention:new` event to each mentioned user's personal socket room.

Entities (all with UUID PKs from the `uuid-ossp` extension):
- `user` — username, full_name, email, password_hash, avatar_url, last_seen_at
- `device_token` — user_id, token, platform (multi-device)
- `conversation` — type (private|group), title, avatar_url
- `conversation_member` — conversation_id, user_id, role, last_read_at

## Prerequisites

- Docker Desktop (running)
- Flutter (stable channel) — for the mobile app
- Node 22+ — only needed if you want to run the backend outside Docker or run the e2e tests
- Android: minSdk 23 (set automatically); iOS: deployment target 15.0 (set automatically — Firebase requires it)

## 1. Run the backend (Dockerized)

```bash
docker compose up -d --build
```

This starts:
- **postgres** (port 5433 on host → 5432 in net) with `uuid-ossp` enabled and the schema in `backend/db/0001-init.sql`
- **backend** (port 3000) — NestJS API + Socket.io gateway

> Host port for Postgres is `5433` to avoid clashes with a local Postgres. Inside the compose network the backend connects to `postgres:5432`, so the host mapping doesn't matter.

Verify:
```bash
curl -s http://localhost:3000/api/auth/login -X POST -H 'Content-Type: application/json' -d '{}' -i   # expect 400 (validation) = up
```

### Run the backend locally (without Docker) instead

```bash
cd backend
cp ../chat-backend.env.example .env
npm install
npm run start:dev   # needs a Postgres at DB_HOST:DB_PORT (default localhost:5433 if you use compose's pg)
```

## 2. Run the end-to-end backend tests

```bash
cd backend
npm install                # installs devDeps incl. socket.io-client
node e2e-test.js           # private chat: register, socket connect, text+sticker, @mention, no-persistence
node e2e-group.js          # group chat: create group, register device tokens, offline FCM push (stub)
```

`e2e-test.js` prints `PASS ✅` when: both sockets connect, text + sticker deliver live, the sender
gets an ack, the recipient gets a `mention:new`, and the message is **not** found in any REST response
(confirming no persistence).

`e2e-group.js` creates a 3-member group, registers FCM tokens for the two offline members, sends a
message, and you'll see `[FcmPushService] [push:stub] -> 2 device(s)` in the backend logs.

## 3. Run the Flutter app

The app talks to the backend at `http://localhost:3000` by default.

```bash
cd mobile
flutter pub get
flutter run                    # macOS desktop / web / iOS sim — uses localhost
```

### Pointing at a different backend / emulator

- **Android emulator:** the emulator's `localhost` is the host's `10.0.2.2`, so run with:
  ```bash
  flutter run --dart-define=BASE_URL=http://10.0.2.2:3000
  ```
- **Physical device / LAN:** use your machine's LAN IP, e.g. `--dart-define=BASE_URL=http://192.168.x.x:3000`.

`Config.baseUrl` in `mobile/lib/services/config.dart` is the single source of truth for the API host.

### Using the app

1. **Register** with a username (e.g. `vothaianh`), full name, email, password (≥8 chars).
2. On another device/sim, register a second user (e.g. `janedoe`).
3. **New chat → Private**, enter the other user's username → opens a chat.
4. Send text, open the **emoji panel** (bottom-left) for **Stickers** and **GIF** tabs.
5. Type `@username` in a message to tag someone — the recipient gets a mention notification.
6. **New chat → Group** to start a group with multiple usernames.
7. Presence dot (online/offline) and typing indicators appear in the chat header.

## 4. FCM push (real, end-to-end)

Push is fully wired on both sides. The app id is **`com.truepilot.chat`** (matches the Firebase
config files provided).

**How it works:**
- **Mobile** (`firebase_core` + `firebase_messaging` + `flutter_local_notifications`): on login the
  `PushService` (`mobile/lib/services/push_service.dart`) initializes Firebase, requests permission,
  fetches the FCM device token, and `POST`s it to `/api/devices/register`. Token refresh re-registers.
  Foreground FCM messages surface as local notifications; background/terminated messages are shown by
  the OS from the FCM `notification` payload. On logout the token is unregistered.
- **Backend** (`PushService` interface + `FcmPushService` via `firebase-admin`): when a message is
  delivered, offline members get an FCM push to all their registered device tokens. With no server
  credentials it logs `[push:stub]` and still works end-to-end (see the e2e tests).

**Mobile Firebase config files** (already provided in this repo):
- Android: `mobile/android/app/google-services.json` (package `com.truepilot.chat`)
- iOS: `mobile/ios/Runner/GoogleService-Info.plist` (bundle `com.truepilot.chat`)

These are **git-ignored**; checked-in templates are `mobile/google-services.example.json` and
`mobile/GoogleService-Info.example.plist`. Each contributor copies a template, fills in their own
Firebase project values (Firebase Console → Project settings → Your apps), and drops the real file
into place.

**Backend Firebase credentials** (server-side `firebase-admin`, needed for the server to actually
*send* pushes):

1. In the Firebase Console, Project settings → Service accounts → generate a new private key (JSON).
2. Base64-encode it and set it as env vars:
   ```bash
   export FIREBASE_CREDENTIALS_BASE64=$(cat serviceAccount.json | base64 | tr -d '\n')
   export FIREBASE_PROJECT_ID=chat-e4afe
   ```
3. Pass them to the backend container via `docker-compose.yml` (the `environment:` block already has
   `FIREBASE_CREDENTIALS_BASE64` and `FIREBASE_PROJECT_ID`) or to your local `backend/.env`.

On startup, `FcmPushService.onModuleInit` initializes `firebase-admin` only if credentials are present,
so the backend never fails to boot without Firebase.

### Notes on the native builds

- **Android:** minSdk is forced to 23 (FCM requirement); core library desugaring is enabled
  (`isCoreLibraryDesugaringEnabled = true` + `desugar_jdk_libs:2.1.4`) because
  `flutter_local_notifications` requires it. The `com.google.gms.google-services` Gradle plugin
  (v4.4.2) is applied in `settings.gradle.kts` + `app/build.gradle.kts`.
- **iOS:** deployment target is 15.0 (Firebase requires it). Firebase is integrated via Swift Package
  Manager (Flutter 3.44 default — no Podfile). `GoogleService-Info.plist` is registered in the
  Runner target's resources (done in `ios/Runner.xcodeproj`).

## API reference

All under `http://localhost:3000/api` (JWT `Authorization: Bearer <token>` except auth endpoints).

| Method | Path | Body | Notes |
|---|---|---|---|
| POST | `/auth/register` | `{ username, fullName, email, password }` | returns `{ accessToken, user }` |
| POST | `/auth/login` | `{ login, password, fcmToken? }` | `login` = username or email |
| GET  | `/users/:username` | — | public-user view (for tagging / starting chats) |
| GET  | `/conversations` | — | list my conversations with members |
| GET  | `/conversations/:id` | — | one conversation view |
| POST | `/conversations/private` | `{ userId }` | creates or reuses a 1:1 |
| POST | `/conversations/group` | `{ title?, memberIds: string[] }` | creates a group |
| POST | `/conversations/:id/members` | `{ memberIds: string[] }` | add members |
| POST | `/conversations/:id/read` | — | mark read |
| POST | `/devices/register` | `{ token, platform? }` | register FCM token |
| DELETE | `/devices/unregister` | `{ token }` | remove a token |

### Socket.io events (path `/socket.io`, transport `websocket`, auth `{ token }`)

Client → Server:
- `message:send` `{ conversationId, type: 'text'|'sticker'|'gif', text?, media?, caption?, clientId? }`
- `typing` `{ conversationId, isTyping }`
- `message:read` `{ conversationId }`
- `conversation:join` `{ conversationId }` (join a newly created conversation's room)

Server → Client:
- `message:new` — the message envelope (delivered live; **not** persisted)
- `message:ack` `{ id, conversationId, createdAt }` — server receipt confirmation
- `mention:new` `{ conversationId, fromUserId, fromUsername, username, preview, createdAt }`
- `typing` `{ conversationId, userId, username, isTyping }`
- `message:read` `{ conversationId, userId, at }`
- `presence:update` `{ userId, online }`

On connect, the server authenticates the JWT from `handshake.auth.token` (or `?token=`), then
auto-joins the socket to every conversation room the user is a member of — so delivery "just works"
for existing conversations without the client doing anything.

## Tech notes & decisions

- **Transport:** Socket.io (per the chosen design) — reliable reconnects, room semantics, easy presence.
- **UUIDs:** all primary keys are UUIDs generated via the `uuid-ossp` extension (`uuid_generate_v4()`),
  satisfying the "postgres with uuid extension" requirement.
- **No message table:** by design. The only proof a message ever existed is the live socket emit and
  (for offline users) an FCM push. This is the spec's central requirement.
- **`synchronize: true`** is on for dev convenience (TypeORM keeps entities/DB in sync). For production,
  set `DB_SYNCHRONIZE=false` and use migrations; `db/0001-init.sql` is the canonical schema.
- **Security:** passwords hashed with bcrypt; JWT auth via a global guard (`@Public()` opts out);
  sockets authenticated from the handshake JWT and disconnected if invalid.

## Troubleshooting

- **`address already in use: 5432`** — a local Postgres is using 5432; the compose file already maps
  the host to `5433`. If 5433 is also taken, change the host port in `docker-compose.yml`.
- **Flutter can't reach backend on Android emulator** — use `--dart-define=BASE_URL=http://10.0.2.2:3000`.
- **No FCM notifications appear** — without `FIREBASE_CREDENTIALS_BASE64` the backend intentionally
  logs `[push:stub]` instead of sending. That's expected; see "Enabling real FCM push" above.
- **`Empty criteria(s)` / `secret or public key must be provided`** — these were earlier bugs; if you
  see them you're on a stale build. `docker compose up -d --build backend` to rebuild.