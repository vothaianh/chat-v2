import { Module } from '@nestjs/common';
import { RealtimeGateway } from './realtime.gateway';
import { PresenceService } from './presence.service';
import { CallsService } from './calls.service';
import { ConversationsModule } from '../conversations/conversations.module';
import { UsersModule } from '../users/users.module';
import { DeviceTokensModule } from '../device-tokens/device-tokens.module';
import { PushModule } from '../push/push.module';

@Module({
  imports: [
    ConversationsModule,
    UsersModule,
    DeviceTokensModule,
    PushModule,
  ],
  providers: [RealtimeGateway, PresenceService, CallsService],
  exports: [PresenceService, CallsService],
})
export class RealtimeModule {}