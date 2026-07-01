import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as admin from 'firebase-admin';
import { PushPayload, PushService } from './push.service';

/**
 * FCM-backed PushService. Initializes firebase-admin only when credentials are
 * provided (base64-encoded service account JSON). When not configured, every
 * send() logs the payload and returns — so the app runs locally with no Firebase
 * project, and you only need to drop in credentials to enable real push.
 */
@Injectable()
export class FcmPushService implements PushService, OnModuleInit {
  private readonly logger = new Logger(FcmPushService.name);
  private configured = false;

  constructor(private readonly config: ConfigService) {}

  onModuleInit() {
    const b64 = this.config.get<string>('firebase.credentialsBase64');
    const projectId = this.config.get<string>('firebase.projectId');
    if (!b64) {
      this.logger.warn('Firebase credentials not set — push will be logged only. Set FIREBASE_CREDENTIALS_BASE64 to enable.');
      return;
    }
    try {
      const decoded = Buffer.from(b64, 'base64').toString('utf8');
      const creds = JSON.parse(decoded);
      admin.initializeApp({
        credential: admin.credential.cert(creds),
        projectId: projectId || creds.project_id,
      });
      this.configured = true;
      this.logger.log('Firebase Admin initialized — push enabled.');
    } catch (err) {
      this.logger.error(`Failed to init Firebase: ${err.message}`);
    }
  }

  async send(tokens: string[], payload: PushPayload): Promise<void> {
    const valid = tokens.filter(Boolean);
    if (!valid.length) return;

    if (!this.configured) {
      // Graceful no-op: surface what would have been sent.
      this.logger.log(
        `[push:stub] -> ${valid.length} device(s)\n  title: ${payload.title}\n  body: ${payload.body}\n  data: ${JSON.stringify(payload.data ?? {})}`,
      );
      return;
    }

    try {
      const res = await admin.messaging().sendEachForMulticast({
        tokens: valid,
        notification: { title: payload.title, body: payload.body },
        data: payload.data ?? {},
        android: { priority: 'high' },
        apns: { payload: { aps: { sound: 'default', badge: 1 } } },
      });
      if (res.failureCount > 0) {
        this.logger.warn(`FCM: ${res.failureCount}/${valid.length} deliveries failed.`);
      }
    } catch (err) {
      this.logger.error(`FCM send error: ${err.message}`);
    }
  }
}