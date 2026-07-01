import { Injectable, Logger } from '@nestjs/common';
import { UsersService } from '../users/users.service';

/**
 * Tracks which users currently have at least one connected socket.
 * Used to decide live socket delivery vs. FCM push for offline recipients,
 * and to expose online/last-seen presence to other clients.
 */
@Injectable()
export class PresenceService {
  private readonly logger = new Logger(PresenceService.name);
  // userId -> Set<socketId>
  private readonly sockets = new Map<string, Set<string>>();

  constructor(private readonly users: UsersService) {}

  async connect(userId: string, socketId: string) {
    if (!this.sockets.has(userId)) this.sockets.set(userId, new Set());
    this.sockets.get(userId)!.add(socketId);
    await this.users.touchLastSeen(userId);
  }

  async disconnect(userId: string, socketId: string) {
    const set = this.sockets.get(userId);
    if (!set) return;
    set.delete(socketId);
    if (set.size === 0) {
      this.sockets.delete(userId);
      await this.users.touchLastSeen(userId);
    }
  }

  isOnline(userId: string): boolean {
    const set = this.sockets.get(userId);
    return !!set && set.size > 0;
  }

  onlineUserIds(): string[] {
    return [...this.sockets.keys()];
  }
}