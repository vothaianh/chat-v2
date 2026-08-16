import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as fs from 'fs';
import * as path from 'path';

type ApnProvider = {
  send: (notification: unknown, tokens: string | string[]) => Promise<{ failed: Array<{ device: string; response?: { reason?: string } }> }>;
  shutdown: () => void;
};

type ApnModule = {
  Provider: new (opts: Record<string, unknown>) => ApnProvider;
  Notification: new () => {
    topic: string;
    pushType: string;
    priority: number;
    expiry: number;
    contentAvailable: number;
    payload: Record<string, unknown>;
  };
};

@Injectable()
export class ApnsVoipService implements OnModuleInit {
  private readonly logger = new Logger(ApnsVoipService.name);
  private apn: ApnModule | null = null;
  private bundleId = 'com.truepilot.chatv2';
  private keyPath = '';
  private keyId = '';
  private teamId = '';

  constructor(private readonly config: ConfigService) {}

  onModuleInit() {
    this.bundleId = (this.config.get<string>('apns.bundleId') ?? process.env.APNS_BUNDLE_ID ?? 'com.truepilot.chatv2').trim();
    this.keyId = (this.config.get<string>('apns.keyId') ?? process.env.APNS_KEY_ID ?? '').trim();
    this.teamId = (this.config.get<string>('apns.teamId') ?? process.env.APNS_TEAM_ID ?? '').trim();
    this.keyPath = (this.config.get<string>('apns.keyPath') ?? process.env.APNS_KEY_PATH ?? '').trim();
    if (!this.keyPath || !this.keyId || !this.teamId) {
      this.logger.warn('APNs VoIP not configured — set APNS_KEY_PATH, APNS_KEY_ID, APNS_TEAM_ID');
      return;
    }
    if (!fs.existsSync(this.keyPath)) {
      this.logger.warn(`APNs key not found at ${this.keyPath}`);
      return;
    }
    try {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      this.apn = require('apn') as ApnModule;
      this.logger.log('APNs VoIP ready');
    } catch (e) {
      this.logger.error(`apn module missing: ${(e as Error).message}`);
    }
  }

  enabled() {
    return !!(this.apn && this.keyPath && this.keyId && this.teamId);
  }

  async send(
    tokens: string[],
    payload: {
      callId: string;
      conversationId: string;
      media: string;
      fromUserId: string;
      fromUsername: string;
      fromFullName: string;
    },
  ) {
    const valid = tokens.filter(Boolean);
    if (!valid.length || !this.apn) return false;
    const key = path.resolve(this.keyPath);
    const noteFactory = () => {
      const note = new this.apn!.Notification();
      note.topic = `${this.bundleId}.voip`;
      note.pushType = 'voip';
      note.priority = 10;
      note.expiry = Math.floor(Date.now() / 1000) + 45;
      note.contentAvailable = 1;
      note.payload = { ...payload, type: 'call' };
      return note;
    };
    let sent = false;
    for (const production of [false, true]) {
      const provider = new this.apn.Provider({
        token: { key, keyId: this.keyId, teamId: this.teamId },
        production,
      });
      try {
        const res = await provider.send(noteFactory(), valid);
        const ok = valid.length - (res.failed?.length ?? 0);
        if (res.failed?.length) {
          this.logger.warn(
            `VoIP ${production ? 'prod' : 'sandbox'}: ${res.failed.length} failed (${res.failed.map((f) => f.response?.reason).join(', ')})`,
          );
        }
        if (ok > 0) {
          sent = true;
          this.logger.log(`VoIP ${production ? 'prod' : 'sandbox'}: sent to ${ok}`);
        }
      } catch (e) {
        this.logger.warn(`VoIP ${production ? 'prod' : 'sandbox'} error: ${(e as Error).message}`);
      } finally {
        provider.shutdown();
      }
    }
    return sent;
  }
}
