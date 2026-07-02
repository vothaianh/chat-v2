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
import * as jwt from 'jsonwebtoken';
import { ConfigService } from '@nestjs/config';
import { Server, Socket } from 'socket.io';
import { SendMessageDto, TypingDto, ReadDto } from './dto';
import { ConversationsService } from '../conversations/conversations.service';
import { UsersService } from '../users/users.service';
import { PresenceService } from './presence.service';
import { extractMentions } from './mentions';
import { PUSH_SERVICE, PushService } from '../push/push.service';
import { DeviceTokensService } from '../device-tokens/device-tokens.service';
import { JwtPayload } from '../auth/jwt.strategy';

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
    private readonly users: UsersService,
    private readonly presence: PresenceService,
    private readonly devices: DeviceTokensService,
    private readonly config: ConfigService,
    @Inject(PUSH_SERVICE) private readonly push: PushService,
  ) {}

  /** Authenticate the socket from the handshake JWT and stamp it on client.data. */
  private authenticate(client: Socket): { userId: string; username: string } | null {
    const token: string =
      client.handshake?.auth?.token || client.handshake?.query?.token || null;
    if (!token) return null;
    const secret = this.config.get<string>('jwt.secret') ?? 'dev-secret-change-me';
    try {
      const payload = jwt.verify(token, secret) as JwtPayload;
      client.data.userId = payload.sub;
      client.data.username = payload.username;
      return { userId: payload.sub, username: payload.username };
    } catch {
      return null;
    }
  }

  async handleConnection(client: Socket) {
    const auth = this.authenticate(client);
    if (!auth) {
      this.logger.warn('WS connect rejected: invalid token');
      client.disconnect(true);
      return;
    }
    const { userId } = auth;
    await this.presence.connect(userId, client.id);

    // Auto-join every conversation the user is a member of for instant delivery.
    const convs = await this.conversations.listMine(userId);
    for (const c of convs) {
      await client.join(this.room(c.id));
    }
    // Personal room for direct delivery (mentions, etc.) to all of a user's devices.
    await client.join(this.userRoom(userId));

    this.broadcastPresence(userId, true);
    this.logger.log(`connected: ${auth.username} (${userId}) — ${convs.length} rooms`);
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
   * Deliver a message. Ephemeral: the envelope is never written to the DB.
   * The server routes it to the conversation room, fans out FCM to offline
   * members, and resolves @mentions.
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

    // 1) Instant delivery to everyone online in the conversation room.
    this.server.to(this.room(dto.conversationId)).emit('message:new', envelope);

    // 2) Delivery ack back to sender (confirms server receipt — messages aren't stored).
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