# Volt

Instant messaging app (**Flutter** + **NestJS** + **Postgres**). Version **1.0.0**.

- Private and group chat with persisted history
- Live delivery over **Socket.io**
- **Emoji**, **sticker** packs, **GIFs**, and **images** (stickers / GIFs / images render without a chat bubble)
- **1:1 voice and video calls** (WebRTC) with call history in the thread
- iOS incoming calls via **CallKit** + **PushKit** VoIP
- Register with **username + full name + email**
- Tag people by username (`@vothaianh`) — mentions resolve and notify
- **FCM** (and VoIP) push to offline recipients (graceful no-op when credentials are missing)
- Two flavors: **dev** (LAN API) and **prod** (`chat-api.truepilot.io`)

## Monorepo layout

```
chat/
├── docker-compose.yml          # optional postgres + backend (prod-style)
├── backend/                    # NestJS API + Socket.io gateway
│   ├── db/0001-init.sql        # uuid extension + schema
│   ├── e2e-test.js             # private chat + persist + mention
│   ├── e2e-group.js            # group + offline-push
│   └── src/
│       ├── auth/               # register/login/JWT
│       ├── users/
│       ├── device-tokens/      # FCM + ios-voip tokens
│       ├── conversations/      # rooms, members, message history
│       ├── realtime/           # Socket.io: chat, presence, mentions, calls
│       ├── push/               # FCM + APNs VoIP
│       ├── uploads/            # image upload / S3
│       └── config/
└── mobile/                     # Flutter app (Volt)
    ├── assets/stickers/        # 20 die-cut sticker packs
    └── lib/
        ├── main_dev.dart / main_prod.dart
        ├── config/app_config.dart
        ├── services/           # api, socket, auth, calls, push, config
        ├── widgets/            # message_bubble, media_picker
        └── screens/            # auth, conversations, chat, call, settings
```

## Architecture

- **Hot path:** `client → Socket.io → gateway → room.emit('message:new')`. The same envelope is **persisted** (`message` table) so history reloads after quit.
- **History:** `GET /api/conversations/:id/messages` (cursor via `before`).
- **Offline:** the gateway looks up FCM tokens (and iOS VoIP tokens for calls) and sends push. Missing credentials log a stub instead of failing the send.
- **Calls:** signaling on the socket (`call:invite` … `call:ice`). Media is peer-to-peer WebRTC (STUN; optional TURN via `TURN_*`). Ended calls are written as a `type: 'call'` history row.
- **Presence:** in-memory `userId → Set<socketId>`. Last-seen is persisted on connect/disconnect.
- **@mentions:** `@username` is resolved and a `mention:new` event is emitted to that user’s personal room.

Entities (UUID PKs via `uuid-ossp`):

- `user` — username, full_name, email, password_hash, avatar_url, last_seen_at
- `device_token` — user_id, token, platform (`ios` | `android` | `web` | `ios-voip`)
- `conversation` / `conversation_member`
- `message` — text | sticker | gif | image | call

## Prerequisites

- **Node 22+** — run the backend with `npm run start:dev` (do not require Docker for local work)
- **Postgres 17** with `uuid-ossp` (ServBay / local / compose). Schema: `backend/db/0001-init.sql`
- **Flutter** (stable)
- Android minSdk 23; iOS deployment target 15.0
- Docker is optional (compose for a containerized API)

## 1. Run the backend (Node)

```bash
cd backend
# create .env with at least:
#   PORT=3010
#   DB_HOST=localhost
#   DB_PORT=5432
#   DB_USER=chat
#   DB_PASSWORD=…
#   DB_NAME=chatdb
#   JWT_SECRET=…
npm install
npm run start:dev
```

Verify:

```bash
curl -s http://localhost:3010/api/auth/login -X POST \
  -H 'Content-Type: application/json' -d '{}' -i
# expect 400 (validation) = up
```

### Optional: Docker

```bash
docker compose up -d --build
```

- **postgres** host `5433` → container `5432`
- **backend** host `3010`

Compose expects an external Docker network named `shared-network`.

## 2. End-to-end backend tests

```bash
cd backend
npm install
node e2e-test.js    # private chat: live text+sticker, @mention, history persist
node e2e-group.js   # group + offline FCM stub
```

`e2e-test.js` prints `PASS` when both sockets connect, text + sticker deliver live, the sender gets an ack, the recipient gets `mention:new`, and the sent text is returned from `GET /conversations/:id/messages`.

## 3. Run the Flutter app

Flavors are defined in `mobile/lib/config/app_config.dart`. **Dev and prod share the same install** (same bundle / application id) so only one Volt is on the device at a time.

| Flavor   | App name  | Endpoint                        | Entrypoint          |
| -------- | --------- | ------------------------------- | ------------------- |
| **dev**  | Volt Dev  | `http://10.0.0.100:3010`        | `lib/main_dev.dart` |
| **prod** | Volt      | `https://chat-api.truepilot.io` | `lib/main_prod.dart` |

iOS bundle id: `com.truepilot.chatv2` (VoIP topic `com.truepilot.chatv2.voip`).  
Android application id: `com.truepilot.chat`.

```bash
cd mobile
flutter pub get

flutter run --flavor dev  -t lib/main_dev.dart
flutter run --flavor prod -t lib/main_prod.dart
```

### Pointing at a different backend

- Override any flavor: `--dart-define=BASE_URL=http://192.168.x.x:3010`
- **Android emulator:** `--dart-define=BASE_URL=http://10.0.2.2:3010` (emulator `localhost` is the host)
- iOS **simulator** can use the host; physical devices need the LAN IP (dev flavor already uses `10.0.0.100`)

### Release builds

```bash
flutter build ipa --flavor prod -t lib/main_prod.dart
flutter build ipa --flavor prod -t lib/main_prod.dart --export-method development

flutter build apk       --flavor prod -t lib/main_prod.dart --release
flutter build appbundle --flavor prod -t lib/main_prod.dart --release
```

iOS schemes live in `mobile/ios/Runner.xcodeproj`; Android flavors in `mobile/android/app/build.gradle.kts`.

### Using the app

1. **Register** with a username (e.g. `vothaianh`), full name, email, password (≥8 chars).
2. On another device, register a second user.
3. **New chat → Private**, enter the other username.
4. Send text. Bottom composer: **emoji** / **sticker** / **gifs**, plus the photo picker.
5. Type `@username` to mention someone.
6. Header **phone** / **video** starts a 1:1 call. Incoming iOS rings via CallKit when a VoIP token is registered.
7. **New chat → Group** for multiple usernames.
8. Presence and typing show in the chat header. The **You** tab shows live API ping in milliseconds.

## Stickers

The media sheet has three tabs: **emoji** (unicode), **sticker** (illustrated packs), **gifs**.

Packs live under `mobile/assets/stickers/<set>/` and are registered in `mobile/lib/services/config.dart`. Every pack includes six faces: **hey**, **love**, **lol**, **wow**, **sad**, **cool**. The **volt** pack also has fire, angry, yes, thanks, sleepy, boom.

| Set        | Label    | Notes                          |
| ---------- | -------- | ------------------------------ |
| `volt`     | volt     | Brand mascot (12 stickers)     |
| `orchid`   | orchid   |                                |
| `aqua`     | aqua     |                                |
| `ghost`    | ghost    |                                |
| `cat`      | ink cat  |                                |
| `star`     | star     |                                |
| `dumpling` | dumpling |                                |
| `moon`     | moon     |                                |
| `flame`    | flame    |                                |
| `heart`    | heart    |                                |
| `bunny`    | bunny    | Personality                    |
| `frog`     | frog     | Personality                    |
| `gremlin`  | gremlin  | Personality                    |
| `fox`      | fox      | Personality                    |
| `panda`    | panda    | Personality                    |
| `alien`    | alien    | Personality                    |
| `cloud`    | cloud    | Personality                    |
| `mushroom` | shroom   | Personality                    |
| `shark`    | shark    | Personality                    |
| `robot`    | robot    | Personality                    |

Add a pack by dropping six `hey.jpg` … `cool.jpg` files into `mobile/assets/stickers/<id>/`, listing the folder in `mobile/pubspec.yaml`, and appending a row to `Config.stickerSets`.

A sticker send uses `type: 'sticker'` and `media` = the asset path (e.g. `assets/stickers/fox/love.jpg`).

## Calls

- Signaling: `call:invite`, `call:incoming` / `call:ringing`, `call:accept` / `call:reject` / `call:cancel` / `call:hangup`, then WebRTC `call:offer` / `call:answer` / `call:ice`.
- Ring timeout is 45 seconds. Busy callee gets `call:busy`.
- ICE: public STUN; optional TURN from `TURN_URL`, `TURN_USERNAME`, `TURN_CREDENTIAL`.
- iOS killed/background: register platform `ios-voip`; the server sends APNs VoIP (`APNS_KEY_PATH`, `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID=com.truepilot.chatv2`).
- When a call ends, a `type: 'call'` message is stored so the thread shows voice/video history.

## 4. FCM and VoIP push

App / Firebase package on Android is **`com.truepilot.chat`**. iOS Volt uses **`com.truepilot.chatv2`**.

**How it works:**

- **Mobile** (`firebase_core` + `firebase_messaging` + `flutter_local_notifications` + `flutter_callkit_incoming`): on login, `PushService` requests permission, registers the FCM token at `/api/devices/register`, and on iOS also registers the PushKit VoIP token as `platform: ios-voip`. Logout unregisters.
- **Backend:** offline chat uses FCM. Incoming calls prefer APNs VoIP, then FCM fallback. Without credentials the services log a stub.

**Mobile Firebase files** (git-ignored; templates checked in):

- Android: `mobile/android/app/google-services.json` — template `mobile/google-services.example.json`
- iOS: `mobile/ios/Runner/GoogleService-Info.plist` — template `mobile/GoogleService-Info.example.plist`

**Backend Firebase** (server send):

1. Firebase Console → Project settings → Service accounts → new private key.
2. Base64-encode and set `FIREBASE_CREDENTIALS_BASE64` + `FIREBASE_PROJECT_ID` in `backend/.env` (or compose).
3. `FcmPushService` initializes `firebase-admin` only when credentials exist.

### Native notes

- **Android:** minSdk 23; core library desugaring on (`desugar_jdk_libs:2.1.4`); Google Services plugin applied. Flavors share `applicationId` so one `google-services.json` matches.
- **iOS:** deployment target 15.0. Camera / mic / local-network / photo usage strings are set for Volt. VoIP topic must stay `com.truepilot.chatv2.voip`.

## API reference

All under `http://localhost:3010/api` (JWT `Authorization: Bearer <token>` except auth).

| Method | Path                              | Body                                      | Notes                                |
| ------ | --------------------------------- | ----------------------------------------- | ------------------------------------ |
| POST   | `/auth/register`                  | `{ username, fullName, email, password }` | `{ accessToken, user }`              |
| POST   | `/auth/login`                     | `{ login, password, fcmToken? }`          | `login` = username or email          |
| GET    | `/users/me`                       | —                                         | current profile (signed avatar)      |
| POST   | `/users/me/avatar`                | multipart `file`                          | set profile photo                    |
| GET    | `/users/:username`                | —                                         | public user for tagging / new chat   |
| GET    | `/conversations`                  | —                                         | my conversations + members           |
| GET    | `/conversations/:id`              | —                                         | one conversation                     |
| GET    | `/conversations/:id/messages`     | `?limit&before`                           | persisted history                    |
| POST   | `/conversations/private`          | `{ userId }`                              | create or reuse 1:1                  |
| POST   | `/conversations/group`            | `{ title?, memberIds }`                   | create group                         |
| POST   | `/conversations/:id/members`      | `{ memberIds }`                           | add members                          |
| POST   | `/conversations/:id/read`         | —                                         | mark read                            |
| POST   | `/uploads/image`                  | multipart `file` + `conversationId`       | image for chat                       |
| POST   | `/uploads/presign`                | `{ conversationId, contentType }`         | S3 presign                           |
| POST   | `/devices/register`               | `{ token, platform? }`                    | `ios` / `android` / `web` / `ios-voip` |
| DELETE | `/devices/unregister`             | `{ token }`                               | remove a token                       |

### Socket.io (path `/socket.io`, transport `websocket`, auth `{ token }`)

Client → server:

- `message:send` `{ conversationId, type: 'text'|'sticker'|'gif'|'image', text?, media?, caption?, clientId? }`
- `typing` `{ conversationId, isTyping }`
- `message:read` `{ conversationId }`
- `conversation:join` `{ conversationId }`
- `call:invite` `{ conversationId, media: 'audio'|'video' }`
- `call:accept` / `call:reject` / `call:cancel` / `call:hangup` `{ callId }`
- `call:offer` / `call:answer` / `call:ice` `{ callId, …sdp/candidate }`

Server → client:

- `message:new` — envelope (also persisted)
- `message:ack` `{ id, conversationId, createdAt }`
- `mention:new` `{ conversationId, fromUserId, fromUsername, username, preview, createdAt }`
- `typing` / `message:read` / `presence:update`
- `call:incoming` / `call:ringing` / `call:accepted` / `call:busy` / `call:ended` (+ ICE servers on invite)

On connect the server authenticates `handshake.auth.token` (or `?token=`) and joins every conversation room the user belongs to.

## Tech notes

- **Transport:** Socket.io — reconnects, rooms, presence.
- **UUIDs:** `uuid-ossp` / `uuid_generate_v4()`.
- **Messages are stored.** Live emit is still the delivery path; the `message` table is history + call records.
- **`synchronize: true`** is on for local TypeORM convenience. Production should set `DB_SYNCHRONIZE=false` and use migrations; `db/0001-init.sql` is the canonical schema.
- **Security:** bcrypt passwords; JWT global guard (`@Public()` opts out); sockets disconnect if the handshake JWT is invalid.

## Troubleshooting

- **`address already in use: 5432`** — compose maps host `5433`. Local Node typically uses host Postgres on `5432` (see `backend/.env`).
- **Flutter can’t reach the backend on a physical device** — use the machine LAN IP (`dev` defaults to `http://10.0.0.100:3010`). Android emulator: `http://10.0.2.2:3010`.
- **No FCM notifications** — without `FIREBASE_CREDENTIALS_BASE64` the backend logs a stub. That’s expected.
- **iOS rings only as a banner, not CallKit** — the device must have registered an `ios-voip` token; APNs env (`APNS_*`) must be set on the API that flavor talks to.
- **Prod call has no audio across networks** — set `TURN_*` so ICE can relay.
- **New stickers missing in the app** — they are Flutter assets; rebuild after adding files / `pubspec.yaml` entries.
