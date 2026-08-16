import { Global, Module } from '@nestjs/common';
import { StorageService } from './storage.service';
import { UploadsController } from './uploads.controller';
import { ConversationsModule } from '../conversations/conversations.module';

@Global()
@Module({
  providers: [StorageService],
  exports: [StorageService],
})
export class StorageModule {}

@Module({
  imports: [ConversationsModule],
  controllers: [UploadsController],
})
export class UploadsModule {}
