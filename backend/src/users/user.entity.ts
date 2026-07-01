import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  OneToMany,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';
import { DeviceToken } from '../device-tokens/device-token.entity';
import { ConversationMember } from '../conversations/conversation-member.entity';

@Entity('user')
export class User {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Index({ unique: true })
  @Column({ length: 64 })
  username: string;

  @Column({ name: 'full_name', length: 128 })
  fullName: string;

  @Index({ unique: true })
  @Column({ length: 255 })
  email: string;

  @Column({ name: 'password_hash', length: 255, select: false })
  passwordHash: string;

  @Column({ name: 'avatar_url', length: 255, nullable: true })
  avatarUrl: string | null;

  @Column({ name: 'last_seen_at', type: 'timestamptz', default: () => 'now()' })
  lastSeenAt: Date;

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;

  @UpdateDateColumn({ type: 'timestamptz' })
  updatedAt: Date;

  @OneToMany(() => DeviceToken, (t) => t.user)
  deviceTokens: DeviceToken[];

  @OneToMany(() => ConversationMember, (m) => m.user)
  memberships: ConversationMember[];
}