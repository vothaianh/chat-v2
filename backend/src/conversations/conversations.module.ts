import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Conversation } from './conversation.entity';
import { ConversationMember } from './conversation-member.entity';
import { Message } from './message.entity';
import { ConversationsService } from './conversations.service';
import { ConversationsController } from './conversations.controller';
import { MessagesService } from './messages.service';
import { UsersModule } from '../users/users.module';

@Module({
  imports: [TypeOrmModule.forFeature([Conversation, ConversationMember, Message]), UsersModule],
  providers: [ConversationsService, MessagesService],
  controllers: [ConversationsController],
  exports: [ConversationsService, MessagesService],
})
export class ConversationsModule {}