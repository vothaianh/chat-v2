import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { FcmPushService } from './fcm-push.service';
import { PUSH_SERVICE, PushService } from './push.service';
import { DeviceTokensModule } from '../device-tokens/device-tokens.module';

@Module({
  imports: [ConfigModule, DeviceTokensModule],
  providers: [
    FcmPushService,
    { provide: PUSH_SERVICE, useExisting: FcmPushService },
  ],
  exports: [FcmPushService, { provide: PUSH_SERVICE, useExisting: FcmPushService }],
})
export class PushModule {}