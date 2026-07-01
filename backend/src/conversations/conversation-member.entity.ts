import {
  Column,
  Entity,
  JoinColumn,
  ManyToOne,
  PrimaryColumn,
} from 'typeorm';
import { Conversation } from './conversation.entity';
import { User } from '../users/user.entity';

@Entity('conversation_member')
export class ConversationMember {
  @PrimaryColumn({ name: 'conversation_id', type: 'uuid' })
  conversationId: string;

  @PrimaryColumn({ name: 'user_id', type: 'uuid' })
  userId: string;

  @ManyToOne(() => Conversation, (c) => c.members, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'conversation_id' })
  conversation: Conversation;

  @ManyToOne(() => User, (u) => u.memberships, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user: User;

  @Column({ type: 'timestamptz', default: () => 'now()' })
  joinedAt: Date;

  @Column({ length: 16, default: 'member' })
  role: 'owner' | 'admin' | 'member';

  @Column({ name: 'last_read_at', type: 'timestamptz', nullable: true })
  lastReadAt: Date | null;
}