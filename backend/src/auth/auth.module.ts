import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { User } from '../users/user.entity';
import { AuthService } from './auth.service';
import { AuthController } from './auth.controller';
import { JwtStrategy } from './jwt.strategy';
import { JwtAuthGuard } from './jwt-auth.guard';
import { UsersModule } from '../users/users.module';
import { DeviceTokensModule } from '../device-tokens/device-tokens.module';

@Module({
  imports: [
    TypeOrmModule.forFeature([User]),
    UsersModule,
    DeviceTokensModule,
    PassportModule,
    JwtModule.registerAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        secret: config.get<string>('jwt.secret') ?? 'dev-secret-change-me',
        signOptions: { expiresIn: (config.get<string>('jwt.expiresIn') ?? '7d') as any },
      }),
    }),
  ],
  providers: [AuthService, JwtStrategy, JwtAuthGuard],
  controllers: [AuthController],
  exports: [AuthService, JwtAuthGuard, JwtModule],
})
export class AuthModule {}