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
    secret: process.env.JWT_SECRET ?? 'dev-secret-change-me',
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
});