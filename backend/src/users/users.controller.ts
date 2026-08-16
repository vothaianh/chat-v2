import {
  BadRequestException,
  Controller,
  Get,
  HttpException,
  HttpStatus,
  Param,
  Post,
  UploadedFile,
  UseInterceptors,
} from '@nestjs/common';
import { FileInterceptor } from '@nestjs/platform-express';
import { memoryStorage } from 'multer';
import { CurrentUser } from '../common/current-user.decorator';
import { UsersService } from './users.service';

@Controller('users')
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Get('me')
  async me(@CurrentUser() user: { sub: string }) {
    const found = await this.users.findById(user.sub);
    if (!found) throw new HttpException('User not found', HttpStatus.NOT_FOUND);
    return this.users.toPublic(found);
  }

  @Post('me/avatar')
  @UseInterceptors(
    FileInterceptor('file', {
      storage: memoryStorage(),
      limits: { fileSize: 10 * 1024 * 1024 },
    }),
  )
  async uploadAvatar(
    @CurrentUser() user: { sub: string },
    @UploadedFile() file: Express.Multer.File,
  ) {
    if (!file) throw new BadRequestException('file is required');
    return this.users.setAvatar(user.sub, file);
  }

  @Get(':username')
  async getByUsername(@Param('username') username: string) {
    const found = await this.users.findByUsername(username.toLowerCase());
    if (!found) throw new HttpException('User not found', HttpStatus.NOT_FOUND);
    return this.users.toPublic(found);
  }
}