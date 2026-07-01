import {
  Column,
  CreateDateColumn,
  Entity,
  Index,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
} from 'typeorm';
import { User } from '../users/user.entity';

@Entity('device_token')
@Index('idx_device_token_user', ['user'])
export class DeviceToken {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'user_id', type: 'uuid' })
  userId: string;

  @ManyToOne(() => User, (u) => u.deviceTokens, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'user_id' })
  user: User;

  @Column({ length: 512 })
  token: string;

  @Column({ length: 16, nullable: true })
  platform: string; // ios | android | web

  @CreateDateColumn({ type: 'timestamptz' })
  createdAt: Date;
}