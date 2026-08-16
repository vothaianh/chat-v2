import {
  Column,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  PrimaryColumn,
} from 'typeorm';
import { Conversation } from './conversation.entity';
import { User } from '../users/user.entity';

export type MessageType = 'text' | 'sticker' | 'gif' | 'image' | 'call';

@Entity('message')
@Index('idx_message_conversation_created', ['conversationId', 'createdAt'])
export class Message {
  /** Client-generated id (optimistic UI) or `${senderId}-${ts}`. */
  @PrimaryColumn({ type: 'varchar', length: 64 })
  id: string;

  @Column({ name: 'conversation_id', type: 'uuid' })
  conversationId: string;

  @ManyToOne(() => Conversation, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'conversation_id' })
  conversation: Conversation;

  @Column({ name: 'sender_id', type: 'uuid' })
  senderId: string;

  @ManyToOne(() => User, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'sender_id' })
  sender: User;

  @Column({ length: 16 })
  type: MessageType;

  @Column({ type: 'text', nullable: true })
  text: string | null;

  @Column({ type: 'varchar', length: 2048, nullable: true })
  media: string | null;

  @Column({ type: 'text', nullable: true })
  caption: string | null;

  @Column({ name: 'created_at', type: 'timestamptz' })
  createdAt: Date;
}
