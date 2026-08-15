import { Body, Controller, Get, HttpException, HttpStatus, Param, Post, Query } from '@nestjs/common';
import { Type } from 'class-transformer';
import {
  ArrayMinSize,
  IsArray,
  IsInt,
  IsOptional,
  IsString,
  IsUUID,
  Max,
  MaxLength,
  Min,
} from 'class-validator';
import { CurrentUser } from '../common/current-user.decorator';
import { ConversationsService } from './conversations.service';
import { MessagesService } from './messages.service';

class ListMessagesQueryDto {
  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(100)
  limit?: number;

  /** Cursor: epoch milliseconds or ISO timestamp of the oldest loaded message. */
  @IsOptional()
  @IsString()
  before?: string;
}

class CreatePrivateDto {
  @IsUUID()
  userId: string;
}

class CreateGroupDto {
  @IsOptional()
  @IsString()
  @MaxLength(128)
  title?: string;

  @IsArray()
  @ArrayMinSize(1)
  @IsUUID('4', { each: true })
  memberIds: string[];

  @IsOptional()
  @IsString()
  avatarUrl?: string;
}

class AddMembersDto {
  @IsArray()
  @IsUUID('4', { each: true })
  memberIds: string[];
}

@Controller('conversations')
export class ConversationsController {
  constructor(
    private readonly conversations: ConversationsService,
    private readonly messages: MessagesService,
  ) {}

  @Get()
  listMine(@CurrentUser() user: { sub: string }) {
    return this.conversations.listMine(user.sub);
  }

  @Get(':id/messages')
  async listMessages(
    @CurrentUser() user: { sub: string },
    @Param('id') id: string,
    @Query() query: ListMessagesQueryDto,
  ) {
    await this.conversations.requireMembership(id, user.sub);
    return this.messages.list(id, { limit: query.limit, before: query.before });
  }

  @Get(':id')
  async getOne(@CurrentUser() user: { sub: string }, @Param('id') id: string) {
    const view = await this.conversations.getConversationView(id, user.sub);
    if (!view) throw new HttpException('Not found', HttpStatus.NOT_FOUND);
    return view;
  }

  @Post('private')
  createPrivate(@CurrentUser() user: { sub: string }, @Body() dto: CreatePrivateDto) {
    return this.conversations.createPrivate(user.sub, dto.userId);
  }

  @Post('group')
  createGroup(@CurrentUser() user: { sub: string }, @Body() dto: CreateGroupDto) {
    return this.conversations.createGroup(user.sub, dto.title ?? null, dto.memberIds, dto.avatarUrl);
  }

  @Post(':id/members')
  addMembers(
    @CurrentUser() user: { sub: string },
    @Param('id') id: string,
    @Body() dto: AddMembersDto,
  ) {
    return this.conversations.addMembers(id, dto.memberIds, user.sub);
  }

  @Post(':id/read')
  markRead(@CurrentUser() user: { sub: string }, @Param('id') id: string) {
    return this.conversations.markRead(id, user.sub);
  }
}