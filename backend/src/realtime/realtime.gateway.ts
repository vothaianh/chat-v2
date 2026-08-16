import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
  WsException,
} from '@nestjs/websockets';
import { Inject, Logger } from '@nestjs/common';
import { Server, Socket } from 'socket.io';
import { SendMessageDto, TypingDto, ReadDto, ReactDto } from './dto';
import { ConversationsService } from '../conversations/conversations.service';
import { MessagesService } from '../conversations/messages.service';
import { UsersService } from '../users/users.service';
import { PresenceService } from './presence.service';
import { CallsService, CallMedia } from './calls.service';
import { extractMentions } from './mentions';
import { PUSH_SERVICE, PushService } from '../push/push.service';
import { ApnsVoipService } from '../push/apns-voip.service';
import { DeviceTokensService } from '../device-tokens/device-tokens.service';
import { randomUUID } from 'crypto';
import { JwtPayload } from '../auth/jwt.strategy';
import { stripBearer, verifyAccessToken } from '../auth/jwt-secrets';

@WebSocketGateway({
  namespace: '/',
  cors: { origin: true, credentials: true },
  path: '/socket.io',
})
export class RealtimeGateway implements OnGatewayConnection, OnGatewayDisconnect {
  private readonly logger = new Logger(RealtimeGateway.name);

  @WebSocketServer()
  server: Server;

  constructor(
    private readonly conversations: ConversationsService,
    private readonly messages: MessagesService,
    private readonly users: UsersService,
    private readonly presence: PresenceService,
    private readonly devices: DeviceTokensService,
    private readonly calls: CallsService,
    private readonly voip: ApnsVoipService,
    @Inject(PUSH_SERVICE) private readonly push: PushService,
  ) {}

  /** Pull the JWT from auth, query, or Authorization — Flutter's websocket
   *  transport often omits handshake.auth. */
  private extractToken(client: Socket): string | null {
    const auth = client.handshake?.auth as { token?: unknown } | undefined;
    const query = client.handshake?.query?.token;
    const header =
      client.handshake?.headers?.authorization ??
      (client.handshake?.headers as { Authorization?: string } | undefined)?.Authorization;
    const raw = auth?.token ?? query ?? header ?? null;
    const value = Array.isArray(raw) ? raw[0] : raw;
    if (typeof value !== 'string' || value.length === 0) return null;
    return stripBearer(value);
  }

  /** Authenticate the socket from the handshake JWT and stamp it on client.data. */
  private authenticate(client: Socket): { userId: string; username: string } | 'missing' | 'invalid' {
    const token = this.extractToken(client);
    if (!token) return 'missing';
    const payload = verifyAccessToken(token) as JwtPayload | null;
    if (!payload?.sub) return 'invalid';
    client.data.userId = payload.sub;
    client.data.username = payload.username;
    return { userId: payload.sub, username: payload.username };
  }

  async handleConnection(client: Socket) {
    const auth = this.authenticate(client);
    if (auth === 'missing' || auth === 'invalid') {
      this.logger.warn(`WS connect rejected: ${auth} token`);
      client.disconnect(true);
      return;
    }
    const { userId } = auth;
    await this.presence.connect(userId, client.id);

    try {
      // Auto-join every conversation the user is a member of for instant delivery.
      const convs = await this.conversations.listMine(userId);
      for (const c of convs) {
        await client.join(this.room(c.id));
      }
      // Personal room for direct delivery (mentions, etc.) to all of a user's devices.
      await client.join(this.userRoom(userId));
      this.broadcastPresence(userId, true);
      this.logger.log(`connected: ${auth.username} (${userId}) — ${convs.length} rooms`);
    } catch (e) {
      this.logger.error(`WS room join failed for ${auth.username}: ${(e as Error).message}`);
      await client.join(this.userRoom(userId));
    }
  }

  async handleDisconnect(client: Socket) {
    const userId: string = client.data.userId;
    if (!userId) return;
    await this.presence.disconnect(userId, client.id);
    if (!this.presence.isOnline(userId)) {
      this.broadcastPresence(userId, false);
    }
    const live = this.calls.findByUser(userId);
    if (live) {
      const reason =
        live.state === 'ringing'
          ? userId === live.callerId
            ? 'cancelled'
            : 'timeout'
          : 'disconnect';
      this.endCall(live.id, reason);
    }
    this.logger.log(`disconnected: ${client.data.username}`);
  }

  /**
   * Deliver a message. Persist to Postgres, then emit to the conversation room,
   * fan out FCM to offline members, and resolve @mentions.
   */
  @SubscribeMessage('message:send')
  async onMessage(
    @ConnectedSocket() client: Socket,
    @MessageBody() dto: SendMessageDto,
  ) {
    const userId: string = client.data.userId;
    const isMember = await this.conversations.isMember(dto.conversationId, userId);
    if (!isMember) throw new WsException('Not a conversation member');
    if (dto.type === 'image' && !dto.media) {
      throw new WsException('Image message requires media');
    }

    const ts = Date.now();
    const sender = await this.users.findById(userId);
    const media = await this.messages.resolveMedia(dto.media ?? null);
    const replyTo = await this.messages.replyPreview(dto.conversationId, dto.replyToId);

    const envelope = {
      id: dto.clientId || `${userId}-${ts}`,
      conversationId: dto.conversationId,
      type: dto.type,
      text: dto.text,
      media,
      caption: dto.caption,
      senderId: userId,
      sender: sender ? await this.users.toPublic(sender) : undefined,
      createdAt: ts,
      reactions: [] as { userId: string; emoji: string }[],
      replyTo,
    };

    try {
      await this.messages.persist({
        id: envelope.id,
        conversationId: dto.conversationId,
        senderId: userId,
        type: dto.type,
        text: dto.text,
        media: dto.media, // persist the key / raw ref, not the signed URL
        caption: dto.caption,
        replyToId: replyTo?.id ?? null,
        createdAt: new Date(ts),
      });
    } catch (e) {
      this.logger.error(`persist failed: ${(e as Error).message}`);
    }

    // Instant delivery to everyone online in the conversation room.
    this.server.to(this.room(dto.conversationId)).emit('message:new', envelope);

    // Delivery ack back to sender (confirms server receipt + persist).
    client.emit('message:ack', { id: envelope.id, conversationId: dto.conversationId, createdAt: ts });

    // 3) @mentions: resolve usernames -> users, emit a 'mentioned' event to them directly.
    if (dto.text) {
      const usernames = extractMentions(dto.text);
      if (usernames.length) {
        const map = await this.users.resolveMentions(usernames);
        for (const [uname, mentionedUserId] of map.entries()) {
          if (mentionedUserId === userId) continue; // self-mention ignored
          this.server.to(this.userRoom(mentionedUserId)).emit('mention:new', {
            conversationId: dto.conversationId,
            fromUserId: userId,
            fromUsername: client.data.username,
            username: uname,
            preview: dto.text.slice(0, 120),
            createdAt: ts,
          });
        }
      }
    }

    // 4) Push to offline members. Compute the title/preview, then fan out tokens.
    this.deliverPushForOffline(dto, envelope).catch((e) =>
      this.logger.error(`push fan-out failed: ${e.message}`),
    );
  }

  @SubscribeMessage('typing')
  onTyping(@ConnectedSocket() client: Socket, @MessageBody() dto: TypingDto) {
    client.to(this.room(dto.conversationId)).emit('typing', {
      conversationId: dto.conversationId,
      userId: client.data.userId,
      username: client.data.username,
      isTyping: dto.isTyping ?? true,
    });
  }

  @SubscribeMessage('message:react')
  async onReact(@ConnectedSocket() client: Socket, @MessageBody() dto: ReactDto) {
    const userId: string = client.data.userId;
    const isMember = await this.conversations.isMember(dto.conversationId, userId);
    if (!isMember) throw new WsException('Not a conversation member');
    const msg = await this.messages.getInConversation(dto.messageId, dto.conversationId);
    if (!msg) throw new WsException('Message not found');
    const reactions = await this.messages.toggleReaction(dto.messageId, userId, dto.emoji);
    const payload = {
      messageId: dto.messageId,
      conversationId: dto.conversationId,
      reactions,
    };
    this.server.to(this.room(dto.conversationId)).emit('message:reaction', payload);
    return payload;
  }

  @SubscribeMessage('message:read')
  async onRead(@ConnectedSocket() client: Socket, @MessageBody() dto: ReadDto) {
    const userId: string = client.data.userId;
    const isMember = await this.conversations.isMember(dto.conversationId, userId);
    if (!isMember) throw new WsException('Not a conversation member');
    await this.conversations.markRead(dto.conversationId, userId);
    client.to(this.room(dto.conversationId)).emit('message:read', {
      conversationId: dto.conversationId,
      userId,
      at: Date.now(),
    });
  }

  // Allow a client to join a newly-created conversation without reconnecting.
  @SubscribeMessage('conversation:join')
  async onJoinRoom(@ConnectedSocket() client: Socket, @MessageBody() body: { conversationId: string }) {
    const userId: string = client.data.userId;
    const isMember = await this.conversations.isMember(body.conversationId, userId);
    if (!isMember) throw new WsException('Not a conversation member');
    await client.join(this.room(body.conversationId));
    return { ok: true };
  }

  @SubscribeMessage('call:invite')
  async onCallInvite(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: { conversationId: string; media?: CallMedia; callId?: string },
  ) {
    const userId: string = client.data.userId;
    if (!body?.conversationId) throw new WsException('conversationId required');
    const media: CallMedia = body.media === 'video' ? 'video' : 'audio';
    await this.conversations.requireMembership(body.conversationId, userId);
    const members = await this.conversations.getMemberIds(body.conversationId);
    const others = members.filter((id) => id !== userId);
    if (others.length !== 1) throw new WsException('Calls are 1:1 only');
    const calleeId = others[0];
    if (this.calls.findByUser(userId) || this.calls.findByUser(calleeId)) {
      client.emit('call:busy', { conversationId: body.conversationId });
      return { ok: false, reason: 'busy' };
    }
    const requested = body.callId ? String(body.callId).slice(0, 64) : '';
    const uuidRe =
      /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
    const callId = uuidRe.test(requested) ? requested : randomUUID();
    const caller = await this.users.findById(userId);
    const call = this.calls.start({
      id: callId,
      conversationId: body.conversationId,
      callerId: userId,
      calleeId,
      media,
      onTimeout: (c) => this.endCall(c.id, 'timeout'),
    });
    const payload = {
      callId: call.id,
      conversationId: call.conversationId,
      media: call.media,
      fromUserId: userId,
      fromUsername: caller?.username ?? client.data.username,
      fromFullName: caller?.fullName ?? client.data.username,
      iceServers: this.calls.iceServers(),
    };
    this.server.to(this.userRoom(calleeId)).emit('call:incoming', payload);
    client.emit('call:ringing', payload);
    // Always push — a "online" socket can still be a locked / backgrounded phone.
    const fromUsername = caller?.username ?? client.data.username ?? '';
    const fromFullName = caller?.fullName ?? fromUsername;
    const fcmTokens = await this.devices.getTokensForUsers([calleeId], { excludePlatform: 'ios-voip' });
    const voipTokens = await this.devices.getTokensForUsers([calleeId], { platform: 'ios-voip' });
    this.logger.log(`call push ${call.id}: voip=${voipTokens.length} fcm=${fcmTokens.length}`);
    let voipSent = false;
    if (voipTokens.length) {
      voipSent = await this.voip.send(voipTokens, {
        callId: call.id,
        conversationId: call.conversationId,
        media,
        fromUserId: userId,
        fromUsername,
        fromFullName,
      });
    }
    // iOS killed/background: VoIP must drive CallKit. An FCM alert on top
    // is only a silent banner and hides the fact CallKit never rang.
    if (!voipSent && fcmTokens.length) {
      await this.push.send(fcmTokens, {
        title: fromFullName || 'Incoming call',
        body: media === 'video' ? 'Incoming video call' : 'Incoming voice call',
        call: true,
        data: {
          type: 'call',
          callId: call.id,
          conversationId: call.conversationId,
          media,
          fromUserId: userId,
          fromUsername,
          fromFullName,
          iceServers: JSON.stringify(this.calls.iceServers()),
        },
      });
    }
    return { ok: true, callId: call.id };
  }

  @SubscribeMessage('call:accept')
  onCallAccept(@ConnectedSocket() client: Socket, @MessageBody() body: { callId: string }) {
    const userId: string = client.data.userId;
    const call = this.calls.find(body?.callId);
    if (!call || call.calleeId !== userId) throw new WsException('Call not found');
    this.calls.activate(call.id);
    this.server.to(this.userRoom(call.callerId)).emit('call:accepted', { callId: call.id });
    return { ok: true };
  }

  @SubscribeMessage('call:reject')
  onCallReject(@ConnectedSocket() client: Socket, @MessageBody() body: { callId: string }) {
    const userId: string = client.data.userId;
    const call = this.calls.find(body?.callId);
    if (!call || (call.calleeId !== userId && call.callerId !== userId)) {
      throw new WsException('Call not found');
    }
    this.endCall(call.id, 'rejected');
    return { ok: true };
  }

  @SubscribeMessage('call:cancel')
  onCallCancel(@ConnectedSocket() client: Socket, @MessageBody() body: { callId: string }) {
    const userId: string = client.data.userId;
    const call = this.calls.find(body?.callId);
    if (!call || call.callerId !== userId) throw new WsException('Call not found');
    this.endCall(call.id, 'cancelled');
    return { ok: true };
  }

  @SubscribeMessage('call:hangup')
  onCallHangup(@ConnectedSocket() client: Socket, @MessageBody() body: { callId: string }) {
    const userId: string = client.data.userId;
    const call = this.calls.find(body?.callId);
    if (!call || (call.calleeId !== userId && call.callerId !== userId)) {
      throw new WsException('Call not found');
    }
    this.endCall(call.id, 'hangup');
    return { ok: true };
  }

  @SubscribeMessage('call:offer')
  onCallOffer(@ConnectedSocket() client: Socket, @MessageBody() body: { callId: string; sdp: unknown }) {
    this.relaySignal(client, body?.callId, 'call:offer', { sdp: body?.sdp });
  }

  @SubscribeMessage('call:answer')
  onCallAnswer(@ConnectedSocket() client: Socket, @MessageBody() body: { callId: string; sdp: unknown }) {
    this.relaySignal(client, body?.callId, 'call:answer', { sdp: body?.sdp });
  }

  @SubscribeMessage('call:ice')
  onCallIce(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: { callId: string; candidate: unknown },
  ) {
    this.relaySignal(client, body?.callId, 'call:ice', { candidate: body?.candidate });
  }

  // ---- helpers ----
  private room(conversationId: string) {
    return `conv:${conversationId}`;
  }

  private userRoom(userId: string) {
    return `user:${userId}`;
  }

  private broadcastPresence(userId: string, online: boolean) {
    this.server.emit('presence:update', { userId, online });
  }

  private relaySignal(client: Socket, callId: string, event: string, extra: Record<string, unknown>) {
    const userId: string = client.data.userId;
    const call = this.calls.find(callId);
    if (!call || (call.callerId !== userId && call.calleeId !== userId)) {
      throw new WsException('Call not found');
    }
    const peer = this.calls.peerOf(call, userId);
    this.server.to(this.userRoom(peer)).emit(event, { callId, ...extra });
  }

  private endCall(callId: string, reason: string) {
    const call = this.calls.end(callId);
    if (!call) return;
    const payload = { callId, reason, conversationId: call.conversationId };
    this.server.to(this.userRoom(call.callerId)).emit('call:ended', payload);
    this.server.to(this.userRoom(call.calleeId)).emit('call:ended', payload);
    this.persistCallHistory(call, reason).catch((e) =>
      this.logger.error(`call history persist failed: ${(e as Error).message}`),
    );
  }

  private async persistCallHistory(
    call: { id: string; conversationId: string; callerId: string; media: CallMedia; state: string; activatedAt?: number },
    reason: string,
  ) {
    const ts = Date.now();
    const durationMs =
      call.state === 'active' && call.activatedAt ? Math.max(0, ts - call.activatedAt) : 0;
    const text = this.callHistoryText(call.media, reason, durationMs);
    const id = `call-${call.id}`.slice(0, 64);
    try {
      await this.messages.persist({
        id,
        conversationId: call.conversationId,
        senderId: call.callerId,
        type: 'call',
        text,
        media: call.media,
        caption: reason,
        createdAt: new Date(ts),
      });
    } catch (e) {
      this.logger.error(`call history persist failed: ${(e as Error).message}`);
    }
    const sender = await this.users.findById(call.callerId);
    this.server.to(this.room(call.conversationId)).emit('message:new', {
      id,
      conversationId: call.conversationId,
      type: 'call',
      text,
      media: call.media,
      caption: reason,
      senderId: call.callerId,
      sender: sender ? await this.users.toPublic(sender) : undefined,
      createdAt: ts,
    });
  }

  private callHistoryText(media: CallMedia, reason: string, durationMs: number) {
    const kind = media === 'video' ? 'Video call' : 'Voice call';
    if (durationMs > 0) {
      return `${kind} · ${this.formatCallDuration(durationMs)}`;
    }
    switch (reason) {
      case 'rejected':
        return `Declined ${kind.toLowerCase()}`;
      case 'cancelled':
        return `Cancelled ${kind.toLowerCase()}`;
      case 'timeout':
        return `Missed ${kind.toLowerCase()}`;
      case 'busy':
        return `Busy · ${kind.toLowerCase()}`;
      case 'disconnect':
        return `${kind} dropped`;
      default:
        return kind;
    }
  }

  private formatCallDuration(ms: number) {
    const total = Math.max(0, Math.round(ms / 1000));
    const h = Math.floor(total / 3600);
    const m = Math.floor((total % 3600) / 60);
    const s = total % 60;
    const two = (n: number) => n.toString().padStart(2, '0');
    if (h > 0) return `${h}:${two(m)}:${two(s)}`;
    return `${m}:${two(s)}`;
  }

  private async deliverPushForOffline(dto: SendMessageDto, envelope: any) {
    const memberIds = await this.conversations.getMemberIds(dto.conversationId);
    const offline = memberIds.filter((id) => id !== envelope.senderId && !this.presence.isOnline(id));
    if (!offline.length) return;

    const sender = envelope.sender;
    const title = sender ? `${sender.fullName ?? sender.username}` : 'New message';
    let body: string;
    switch (dto.type) {
      case 'gif':
        body = dto.caption ? `${dto.caption} [GIF]` : '📷 GIF';
        break;
      case 'sticker':
        body = '🎨 Sticker';
        break;
      case 'image':
        body = dto.caption?.trim() ? dto.caption : '📷 Photo';
        break;
      default:
        body = dto.text || '';
    }
    if (dto.text && dto.text.includes('@')) {
      const mentioned = extractMentions(dto.text);
      if (mentioned.length) body = `${body}`;
    }

    const tokens = await this.devices.getTokensForUsers(offline);
    if (!tokens.length) return;

    await this.push.send(tokens, {
      title,
      body,
      data: {
        conversationId: dto.conversationId,
        type: dto.type,
        text: dto.text ?? '',
        media: dto.media ?? '',
        caption: dto.caption ?? '',
        senderId: envelope.senderId,
        senderUsername: envelope.sender?.username ?? '',
        senderFullName: envelope.sender?.fullName ?? '',
        messageId: envelope.id,
        ts: String(envelope.createdAt),
      },
    });
  }
}