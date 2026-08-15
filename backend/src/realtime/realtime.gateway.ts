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
import { SendMessageDto, TypingDto, ReadDto } from './dto';
import { ConversationsService } from '../conversations/conversations.service';
import { MessagesService } from '../conversations/messages.service';
import { UsersService } from '../users/users.service';
import { PresenceService } from './presence.service';
import { extractMentions } from './mentions';
import { PUSH_SERVICE, PushService } from '../push/push.service';
import { DeviceTokensService } from '../device-tokens/device-tokens.service';
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

    const ts = Date.now();
    const sender = await this.users.findById(userId);

    const envelope = {
      id: dto.clientId || `${userId}-${ts}`,
      conversationId: dto.conversationId,
      type: dto.type,
      text: dto.text,
      media: dto.media,
      caption: dto.caption,
      senderId: userId,
      sender: sender ? this.users.toPublic(sender) : undefined,
      createdAt: ts,
    };

    try {
      await this.messages.persist({
        id: envelope.id,
        conversationId: dto.conversationId,
        senderId: userId,
        type: dto.type,
        text: dto.text,
        media: dto.media,
        caption: dto.caption,
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