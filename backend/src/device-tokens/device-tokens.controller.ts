import { Body, Controller, Delete, Post } from '@nestjs/common';
import { IsIn, IsOptional, IsString } from 'class-validator';
import { CurrentUser } from '../common/current-user.decorator';
import { DeviceTokensService } from './device-tokens.service';

class RegisterTokenDto {
  @IsString()
  token: string;

  @IsOptional()
  @IsIn(['ios', 'android', 'web'])
  platform?: string;
}

@Controller('devices')
export class DeviceTokensController {
  constructor(private readonly devices: DeviceTokensService) {}

  @Post('register')
  register(@CurrentUser() user: { sub: string }, @Body() dto: RegisterTokenDto) {
    return this.devices.register(user.sub, dto.token, dto.platform);
  }

  @Delete('unregister')
  unregister(@CurrentUser() user: { sub: string }, @Body() dto: RegisterTokenDto) {
    return this.devices.unregister(user.sub, dto.token);
  }
}