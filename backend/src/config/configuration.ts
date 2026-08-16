export default () => ({
  port: parseInt(process.env.PORT ?? '3000', 10),
  db: {
    host: process.env.DB_HOST ?? 'localhost',
    port: parseInt(process.env.DB_PORT ?? '5432', 10),
    user: process.env.DB_USER ?? 'chat',
    password: process.env.DB_PASSWORD ?? 'chat',
    name: process.env.DB_NAME ?? 'chatdb',
    synchronize: process.env.DB_SYNCHRONIZE === 'true' || true,
  },
  jwt: {
    secret: process.env.JWT_SECRET ?? 'change-me-in-production-please',
    expiresIn: process.env.JWT_EXPIRES_IN ?? '7d',
  },
  cors: {
    origin: process.env.CORS_ORIGIN ?? '*',
  },
  socket: {
    path: process.env.SOCKET_IO_PATH ?? '/socket.io',
  },
  firebase: {
    // base64-encoded service account JSON; empty => push service logs only
    credentialsBase64: process.env.FIREBASE_CREDENTIALS_BASE64 ?? '',
    projectId: process.env.FIREBASE_PROJECT_ID ?? '',
  },
  s3: {
    accessKeyId: process.env.AWS_ACCESS_KEY_ID ?? '',
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY ?? '',
    region: process.env.AWS_REGION ?? 'ap-southeast-1',
    bucket: process.env.AWS_BUCKET ?? '',
  },
  turn: {
    url: process.env.TURN_URL ?? '',
    username: process.env.TURN_USERNAME ?? '',
    credential: process.env.TURN_CREDENTIAL ?? '',
  },
  apns: {
    keyPath: process.env.APNS_KEY_PATH ?? '',
    keyId: process.env.APNS_KEY_ID ?? '',
    teamId: process.env.APNS_TEAM_ID ?? '',
    bundleId: process.env.APNS_BUNDLE_ID ?? 'com.truepilot.chatv2',
  },
});