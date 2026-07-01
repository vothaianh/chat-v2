import {
  Column,
  CreateDateColumn,
  Entity,
  OneToMany,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';
import { ConversationMember } from './conversation-member.entity';

@Entity('conversation')
export class Conversation {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ length: 16 }) // private | group
  type: 'private' | 'group';

  @Column({ length: 128, nullable: true })
  title: string | null;

  @Column({ name: 'avatar_url', length: 255, nullable: true })
  avatarUrl: string | null;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt: Date;

  @OneToMany(() => ConversationMember, (m) => m.conversation)
  members: ConversationMember[];
}