import { IsBoolean, IsIn, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';

/**
 * Message envelope delivered over the socket. The server does NOT persist these —
 * it routes them to the conversation room and to offline recipients' push tokens.
 */
export class SendMessageDto {
  @IsUUID()
  conversationId: string;

  /** text | sticker | gif */
  @IsIn(['text', 'sticker', 'gif'])
  type: 'text' | 'sticker' | 'gif';

  @IsOptional()
  @IsString()
  @MaxLength(4000)
  text?: string;

  // for sticker: a sticker asset id/ref; for gif: a GIF url
  @IsOptional()
  @IsString()
  @MaxLength(512)
  media?: string;

  @IsOptional()
  @IsString()
  @MaxLength(2000)
  caption?: string;

  @IsOptional()
  @IsString()
  clientId?: string; // client-generated id for dedup/optimistic UI

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