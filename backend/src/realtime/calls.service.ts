import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export type CallMedia = 'audio' | 'video';

export type ActiveCall = {
  id: string;
  conversationId: string;
  callerId: string;
  calleeId: string;
  media: CallMedia;
  state: 'ringing' | 'active';
  createdAt: number;
  activatedAt?: number;
};

const RING_MS = 45_000;

@Injectable()
export class CallsService {
  private readonly logger = new Logger(CallsService.name);
  private readonly byId = new Map<string, ActiveCall>();
  private readonly byUser = new Map<string, string>();
  private readonly timers = new Map<string, NodeJS.Timeout>();

  constructor(private readonly config: ConfigService) {}

  iceServers(): Array<Record<string, unknown>> {
    const servers: Array<Record<string, unknown>> = [
      { urls: 'stun:stun.l.google.com:19302' },
      { urls: 'stun:stun1.l.google.com:19302' },
    ];
    const turnUrl = (this.config.get<string>('turn.url') ?? process.env.TURN_URL ?? '').trim();
    const turnUser = (this.config.get<string>('turn.username') ?? process.env.TURN_USERNAME ?? '').trim();
    const turnCred = (this.config.get<string>('turn.credential') ?? process.env.TURN_CREDENTIAL ?? '').trim();
    if (turnUrl) {
      const urls = turnUrl.includes('?')
        ? [turnUrl]
        : [`${turnUrl}?transport=udp`, `${turnUrl}?transport=tcp`];
      servers.push({
        urls,
        username: turnUser || undefined,
        credential: turnCred || undefined,
      });
    }
    return servers;
  }

  find(id: string) {
    return this.byId.get(id);
  }

  findByUser(userId: string) {
    const id = this.byUser.get(userId);
    return id ? this.byId.get(id) : undefined;
  }

  peerOf(call: ActiveCall, userId: string) {
    return userId === call.callerId ? call.calleeId : call.callerId;
  }

  start(input: {
    id: string;
    conversationId: string;
    callerId: string;
    calleeId: string;
    media: CallMedia;
    onTimeout: (call: ActiveCall) => void;
  }): ActiveCall {
    const call: ActiveCall = {
      ...input,
      state: 'ringing',
      createdAt: Date.now(),
    };
    this.byId.set(call.id, call);
    this.byUser.set(call.callerId, call.id);
    this.byUser.set(call.calleeId, call.id);
    const t = setTimeout(() => {
      const current = this.byId.get(call.id);
      if (current?.state === 'ringing') {
        this.end(call.id);
        input.onTimeout(current);
      }
    }, RING_MS);
    this.timers.set(call.id, t);
    this.logger.log(`call ${call.id} ringing ${call.callerId} -> ${call.calleeId} (${call.media})`);
    return call;
  }

  activate(id: string) {
    const call = this.byId.get(id);
    if (!call) return null;
    call.state = 'active';
    call.activatedAt = Date.now();
    const t = this.timers.get(id);
    if (t) clearTimeout(t);
    this.timers.delete(id);
    return call;
  }

  end(id: string) {
    const call = this.byId.get(id);
    if (!call) return null;
    this.byId.delete(id);
    if (this.byUser.get(call.callerId) === id) this.byUser.delete(call.callerId);
    if (this.byUser.get(call.calleeId) === id) this.byUser.delete(call.calleeId);
    const t = this.timers.get(id);
    if (t) clearTimeout(t);
    this.timers.delete(id);
    return call;
  }
}
