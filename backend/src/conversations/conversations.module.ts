import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Conversation } from './conversation.entity';
import { ConversationMember } from './conversation-member.entity';
import { ConversationsService } from './conversations.service';
import { ConversationsController } from './conversations.controller';
import { UsersModule } from '../users/users.module';

@Module({
  imports: [TypeOrmModule.forFeature([Conversation, ConversationMember]), UsersModule],
  providers: [ConversationsService],
  controllers: [ConversationsController],
  exports: [ConversationsService],
})
export class ConversationsModule {}