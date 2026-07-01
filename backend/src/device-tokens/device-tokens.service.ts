import { Injectable, Logger } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { DeviceToken } from './device-token.entity';

@Injectable()
export class DeviceTokensService {
  private readonly logger = new Logger(DeviceTokensService.name);

  constructor(
    @InjectRepository(DeviceToken)
    private readonly repo: Repository<DeviceToken>,
  ) {}

  /** Register (idempotent) an FCM token for a user. */
  async register(userId: string, token: string, platform?: string) {
    if (!token) return;
    const existing = await this.repo.findOne({ where: { userId, token } });
    if (existing) {
      if (platform && existing.platform !== platform) {
        existing.platform = platform;
        await this.repo.save(existing);
      }
      return existing;
    }
    return this.repo.save(this.repo.create({ userId, token, platform }));
  }

  /** Remove a token (e.g. on logout). */
  async unregister(userId: string, token: string) {
    if (!token) return;
    await this.repo.delete({ userId, token });
  }

  /** All FCM tokens for a user (multi-device fan-out). */
  async getTokensForUser(userId: string): Promise<string[]> {
    const rows = await this.repo.find({ where: { userId } });
    return rows.map((r) => r.token).filter(Boolean);
  }

  async getTokensForUsers(userIds: string[]): Promise<string[]> {
    const rows = await this.repo
      .createQueryBuilder('t')
      .where('t.userId IN (:...ids)', { ids: userIds })
      .getMany();
    return rows.map((r) => r.token).filter(Boolean);
  }
}