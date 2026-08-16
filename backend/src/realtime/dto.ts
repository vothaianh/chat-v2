import { IsBoolean, IsIn, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

/**
 * Message envelope delivered over the socket. The server does NOT persist these —
 * it routes them to the conversation room and to offline recipients' push tokens.
 */
export class SendMessageDto {
  @IsUUID()
  conversationId: string;

  /** text | sticker | gif | image */
  @IsIn(['text', 'sticker', 'gif', 'image'])
  type: 'text' | 'sticker' | 'gif' | 'image';

  @IsOptional()
  @IsString()
  @MaxLength(4000)
  text?: string;

  // for sticker: a sticker asset id/ref; for gif: a GIF url
  @IsOptional()
  @IsString()
  @MaxLength(2048)
  media?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  caption?: string;

  @IsOptional()
  @IsString()
  clientId?: string; // client-generated id for dedup/optimistic UI

  @IsOptional()
  @IsString()
  @MaxLength(64)
  replyToId?: string;

  constructor(partial: Partial<SendMessageDto>) {
    Object.assign(this, partial);
  }
}

export class TypingDto {
  @IsUUID()
  conversationId: string;

  @IsOptional()
  @IsBoolean()
  isTyping?: boolean;
}

export class ReadDto {
  @IsUUID()
  conversationId: string;
}

export class ReactDto {
  @IsUUID()
  conversationId: string;

  @IsString()
  @MaxLength(64)
  messageId: string;

  @IsString()
  @MaxLength(16)
  emoji: string;
}