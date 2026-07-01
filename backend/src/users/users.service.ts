import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository } from 'typeorm';
import { User } from './user.entity';

@Injectable()
export class UsersService {
  constructor(
    @InjectRepository(User) private readonly users: Repository<User>,
  ) {}

  findById(id: string) {
    return this.users.findOne({ where: { id } });
  }

  findByUsername(username: string) {
    return this.users.findOne({ where: { username } });
  }

  findByEmail(email: string) {
    return this.users.findOne({ where: { email } });
  }

  findByUsernameOrEmail(login: string) {
    return this.users.findOne({
      where: [{ username: login }, { email: login }],
    });
  }

  findManyByIds(ids: string[]) {
    return this.users.find({ where: ids.map((id) => ({ id })) });
  }

  // Resolve @mentions of the form "@username" to user ids.
  // Returns a map username -> userId for those that exist.
  async resolveMentions(usernames: string[]): Promise<Map<string, string>> {
    const unique = [...new Set(usernames.map((u) => u.toLowerCase()))];
    const out = new Map<string, string>();
    for (const uname of unique) {
      const user = await this.findByUsername(uname);
      if (user) out.set(uname, user.id);
    }
    return out;
  }

  touchLastSeen(id: string) {
    return this.users.update(id, { lastSeenAt: new Date() });
  }

  async listByIds(ids: string[]) {
    const users = await this.findManyByIds(ids);
    return users.map((u) => this.toPublic(u));
  }

  toPublic(u: User) {
    return {
      id: u.id,
      username: u.username,
      fullName: u.fullName,
      avatarUrl: u.avatarUrl,
      lastSeenAt: u.lastSeenAt,
    };
  }
}