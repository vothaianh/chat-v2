import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { Message, MessageType } from './message.entity';
import { MessageReaction } from './message-reaction.entity';
import { Conversation } from './conversation.entity';
import { UsersService } from '../users/users.service';
import { StorageService } from '../uploads/storage.service';

export type PersistMessageInput = {
  id: string;
  conversationId: string;
  senderId: string;
  type: MessageType;
  text?: string | null;
  media?: string | null;
  caption?: string | null;
  createdAt: Date;
};

/** Wire shape shared by the socket envelope and REST responses. */
export type MessageEnvelope = {
  id: string;
  conversationId: string;
  type: MessageType;
  text: string | null;
  media: string | null;
  caption: string | null;
  senderId: string;
  sender?: {
    id: string;
    username: string;
    fullName: string;
    avatarUrl: string | null;
    lastSeenAt: Date;
  };
  createdAt: number;
  reactions: { userId: string; emoji: string }[];
};

@Injectable()
export class MessagesService {
  constructor(
    @InjectRepository(Message)
    private readonly messages: Repository<Message>,
    @InjectRepository(MessageReaction)
    private readonly reactions: Repository<MessageReaction>,
    @InjectRepository(Conversation)
    private readonly conversations: Repository<Conversation>,
    private readonly users: UsersService,
    private readonly storage: StorageService,
  ) {}

  async persist(input: PersistMessageInput): Promise<void> {
    await this.messages
      .createQueryBuilder()
      .insert()
      .into(Message)
      .values({
        id: input.id.slice(0, 64),
        conversationId: input.conversationId,
        senderId: input.senderId,
        type: input.type,
        text: input.text ?? null,
        media: input.media ?? null,
        caption: input.caption ?? null,
        createdAt: input.createdAt,
      })
      .orIgnore()
      .execute();
    await this.conversations.update(input.conversationId, {
      updatedAt: input.createdAt,
    });
  }

  async list(
    conversationId: string,
    opts: { limit?: number; before?: string } = {},
  ): Promise<{ messages: MessageEnvelope[]; hasMore: boolean }> {
    const take = Math.min(Math.max(opts.limit ?? 50, 1), 100);
    const before = this.parseBefore(opts.before);

    const qb = this.messages
      .createQueryBuilder('m')
      .where('m.conversationId = :conversationId', { conversationId })
      .orderBy('m.createdAt', 'DESC')
      .addOrderBy('m.id', 'DESC')
      .take(take + 1);
    if (before) {
      qb.andWhere('m.createdAt < :before', { before });
    }

    const rows = await qb.getMany();
    const hasMore = rows.length > take;
    const page = rows.slice(0, take).reverse();
    return { messages: await this.toEnvelopes(page), hasMore };
  }

  async latestEnvelopes(conversationIds: string[]): Promise<Map<string, MessageEnvelope>> {
    const out = new Map<string, MessageEnvelope>();
    if (!conversationIds.length) return out;

    const rows = await this.messages
      .createQueryBuilder('m')
      .distinctOn(['m.conversationId'])
      .where('m.conversationId IN (:...ids)', { ids: conversationIds })
      .orderBy('m.conversationId')
      .addOrderBy('m.createdAt', 'DESC')
      .addOrderBy('m.id', 'DESC')
      .getMany();

    const envelopes = await this.toEnvelopes(rows);
    for (const env of envelopes) out.set(env.conversationId, env);
    return out;
  }

  resolveMedia(media: string | null | undefined) {
    return this.storage.resolveMedia(media ?? null);
  }

  async getInConversation(id: string, conversationId: string): Promise<Message | null> {
    return this.messages.findOne({ where: { id, conversationId } });
  }

  /** Toggle: same emoji removes, different emoji replaces. One reaction per user. */
  async toggleReaction(
    messageId: string,
    userId: string,
    emoji: string,
  ): Promise<{ userId: string; emoji: string }[]> {
    const clean = emoji.trim().slice(0, 16);
    if (!clean) return this.listReactions([messageId]).then((m) => m.get(messageId) ?? []);

    const existing = await this.reactions.findOne({ where: { messageId, userId } });
    if (existing && existing.emoji === clean) {
      await this.reactions.delete({ id: existing.id });
    } else if (existing) {
      existing.emoji = clean;
      await this.reactions.save(existing);
    } else {
      await this.reactions.insert({ messageId, userId, emoji: clean });
    }
    const map = await this.listReactions([messageId]);
    return map.get(messageId) ?? [];
  }

  async listReactions(
    messageIds: string[],
  ): Promise<Map<string, { userId: string; emoji: string }[]>> {
    const out = new Map<string, { userId: string; emoji: string }[]>();
    for (const id of messageIds) out.set(id, []);
    if (!messageIds.length) return out;
    const rows = await this.reactions
      .createQueryBuilder('r')
      .where('r.messageId IN (:...ids)', { ids: messageIds })
      .orderBy('r.createdAt', 'ASC')
      .getMany();
    for (const r of rows) {
      out.get(r.messageId)?.push({ userId: r.userId, emoji: r.emoji });
    }
    return out;
  }

  async unreadCounts(userId: string, conversationIds: string[]): Promise<Map<string, number>> {
    const out = new Map<string, number>();
    if (!conversationIds.length) return out;

    const rows: Array<{ conversationId: string; count: string }> = await this.messages
      .createQueryBuilder('m')
      .select('m.conversation_id', 'conversationId')
      .addSelect('COUNT(*)', 'count')
      .innerJoin(
        'conversation_member',
        'cm',
        'cm.conversation_id = m.conversation_id AND cm.user_id = :userId',
        { userId },
      )
      .where('m.conversation_id IN (:...ids)', { ids: conversationIds })
      .andWhere('m.sender_id != :userId', { userId })
      .andWhere('(cm.last_read_at IS NULL OR m.created_at > cm.last_read_at)')
      .groupBy('m.conversation_id')
      .getRawMany();

    for (const row of rows) {
      out.set(row.conversationId, parseInt(row.count, 10) || 0);
    }
    return out;
  }

  private async toEnvelopes(rows: Message[]): Promise<MessageEnvelope[]> {
    if (!rows.length) return [];
    const senderIds = [...new Set(rows.map((r) => r.senderId))];
    const senders = await this.users.listByIds(senderIds);
    const byId = new Map(senders.map((s) => [s.id, s]));
    const reactionMap = await this.listReactions(rows.map((r) => r.id));
    return Promise.all(
      rows.map(async (m) => {
        const sender = byId.get(m.senderId);
        return {
          id: m.id,
          conversationId: m.conversationId,
          type: m.type,
          text: m.text,
          media: await this.storage.resolveMedia(m.media),
          caption: m.caption,
          senderId: m.senderId,
          sender,
          createdAt: m.createdAt.getTime(),
          reactions: reactionMap.get(m.id) ?? [],
        };
      }),
    );
  }

  private parseBefore(before?: string): Date | undefined {
    if (!before) return undefined;
    const n = Number(before);
    if (Number.isFinite(n) && n > 1e11) return new Date(n);
    if (Number.isFinite(n) && n > 1e9) return new Date(n * 1000);
    const d = new Date(before);
    return Number.isNaN(d.getTime()) ? undefined : d;
  }
}
