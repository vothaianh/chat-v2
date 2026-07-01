import { Injectable, HttpException, HttpStatus } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { In, Repository } from 'typeorm';
import { Conversation } from './conversation.entity';
import { ConversationMember } from './conversation-member.entity';
import { UsersService } from '../users/users.service';

@Injectable()
export class ConversationsService {
  constructor(
    @InjectRepository(Conversation)
    private readonly conversations: Repository<Conversation>,
    @InjectRepository(ConversationMember)
    private readonly members: Repository<ConversationMember>,
    private readonly users: UsersService,
  ) {}

  /** Create a 1:1 conversation. Reuses an existing one if both users already share a private one. */
  async createPrivate(currentUserId: string, otherUserId: string) {
    if (currentUserId === otherUserId) {
      throw new HttpException('Cannot chat with yourself', HttpStatus.BAD_REQUEST);
    }
    // look for existing private conversation with exactly these two members
    const existing = await this.conversations
      .createQueryBuilder('c')
      .innerJoin('c.members', 'm', 'm.userId IN (:...ids)', {
        ids: [currentUserId, otherUserId],
      })
      .where('c.type = :type', { type: 'private' })
      .groupBy('c.id')
      .having('COUNT(DISTINCT m.userId) = 2')
      .getOne();
    if (existing) return this.getConversationView(existing.id, currentUserId);

    const conv = await this.conversations.save(
      this.conversations.create({ type: 'private' }),
    );
    await this.members.save([
      this.members.create({ conversationId: conv.id, userId: currentUserId, role: 'owner' }),
      this.members.create({ conversationId: conv.id, userId: otherUserId, role: 'member' }),
    ]);
    return this.getConversationView(conv.id, currentUserId);
  }

  /** Create a group conversation with the creator + initial member ids. */
  async createGroup(
    creatorId: string,
    title: string | null,
    memberIds: string[],
    avatarUrl?: string | null,
  ) {
    const unique = [...new Set([creatorId, ...memberIds])];
    const conv = await this.conversations.save(
      this.conversations.create({ type: 'group', title, avatarUrl: avatarUrl ?? null }),
    );
    await this.members.save(
      unique.map((userId, idx) =>
        this.members.create({
          conversationId: conv.id,
          userId,
          role: userId === creatorId ? 'owner' : 'member',
        }),
      ),
    );
    return this.getConversationView(conv.id, creatorId);
  }

  async addMembers(conversationId: string, memberIds: string[], byUserId: string) {
    await this.requireMembership(conversationId, byUserId);
    const existing = await this.members.find({
      where: { conversationId, userId: In(memberIds) },
    });
    const already = new Set(existing.map((m) => m.userId));
    const toAdd = memberIds.filter((id) => !already.has(id));
    if (toAdd.length) {
      await this.members.save(
        toAdd.map((userId) =>
          this.members.create({ conversationId, userId, role: 'member' }),
        ),
      );
    }
  }

  async removeMember(conversationId: string, userId: string) {
    await this.members.delete({ conversationId, userId });
  }

  async listMine(userId: string) {
    const memberships = await this.members.find({
      where: { userId },
      relations: ['conversation'],
    });
    const views = await Promise.all(
      memberships.map((m) => this.getConversationView(m.conversationId, userId)),
    );
    return views.filter(Boolean);
  }

  async getConversationView(conversationId: string, forUserId: string) {
    const conv = await this.conversations.findOne({ where: { id: conversationId } });
    if (!conv) return null;
    const members = await this.members.find({ where: { conversationId } });
    const users = await this.users.listByIds(members.map((m) => m.userId));
    return {
      id: conv.id,
      type: conv.type,
      title: conv.title,
      avatarUrl: conv.avatarUrl,
      createdAt: conv.createdAt,
      members: members.map((m) => {
        const u = users.find((x) => x.id === m.userId);
        return {
          userId: m.userId,
          role: m.role,
          joinedAt: m.joinedAt,
          username: u?.username,
          fullName: u?.fullName,
          avatarUrl: u?.avatarUrl,
        };
      }),
    };
  }

  async getMemberIds(conversationId: string): Promise<string[]> {
    const members = await this.members.find({ where: { conversationId } });
    return members.map((m) => m.userId);
  }

  async isMember(conversationId: string, userId: string): Promise<boolean> {
    const m = await this.members.findOne({ where: { conversationId, userId } });
    return !!m;
  }

  async requireMembership(conversationId: string, userId: string) {
    if (!(await this.isMember(conversationId, userId))) {
      throw new HttpException('Not a conversation member', HttpStatus.FORBIDDEN);
    }
  }

  async markRead(conversationId: string, userId: string) {
    await this.members.update({ conversationId, userId }, { lastReadAt: new Date() });
  }
}