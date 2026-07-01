import { Controller, Get, HttpException, HttpStatus, Param } from '@nestjs/common';
import { UsersService } from './users.service';

// Lookup by username (used for "tag others by username" / start chat).
@Controller('users')
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Get(':username')
  async getByUsername(@Param('username') username: string) {
    const user = await this.users.findByUsername(username.toLowerCase());
    if (!user) throw new HttpException('User not found', HttpStatus.NOT_FOUND);
    return this.users.toPublic(user);
  }
}