import {
  BadRequestException,
  Body,
  Controller,
  Post,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';
import { memoryStorage } from 'multer';
import { CurrentUser } from '../common/current-user.decorator';
import { ConversationsService } from '../conversations/conversations.service';
import { StorageService } from './storage.service';

class PresignDto {
  @IsUUID()
  conversationId: string;

  @IsString()
  @MaxLength(64)
  contentType: string;

  @IsOptional()
  @IsString()
  @MaxLength(128)
  fileName?: string;
}

const MAX_BYTES = 10 * 1024 * 1024;

@Controller('uploads')
export class UploadsController {
  constructor(
    private readonly storage: StorageService,
    private readonly conversations: ConversationsService,
  ) {}

  @Post('image')
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      limits: { fileSize: MAX_BYTES },
    }),
  )
  async uploadImage(
    @CurrentUser() user: { sub: string },
    @UploadedFile() file: Express.Multer.File,
    @Body('conversationId') conversationId: string,
  ) {
    if (!file) throw new BadRequestException('file is required');
    if (!conversationId) throw new BadRequestException('conversationId is required');
    await this.conversations.requireMembership(conversationId, user.sub);
    const sniffed = this.storage.sniffImageType({
      buffer: file.buffer,
      mimetype: file.mimetype,
      filename: file.originalname,
    });
    if (!sniffed) {
      throw new BadRequestException('Unsupported image type');
    }
    const uploaded = await this.storage.uploadBuffer({
      userId: user.sub,
      buffer: file.buffer,
      contentType: sniffed.contentType,
    });
    return { key: uploaded.key, url: uploaded.url };
  }

  @Post('presign')
  async presign(@CurrentUser() user: { sub: string }, @Body() dto: PresignDto) {
    await this.conversations.requireMembership(dto.conversationId, user.sub);
    const sniffed = this.storage.sniffImageType({
      mimetype: dto.contentType,
      filename: dto.fileName,
    });
    if (!sniffed) {
      throw new BadRequestException('Unsupported image type');
    }
    return this.storage.presignPut({
      userId: user.sub,
      contentType: sniffed.contentType,
    });
  }
}
