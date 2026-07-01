import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { APP_GUARD } from '@nestjs/core';
import configuration from './config/configuration';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { DeviceTokensModule } from './device-tokens/device-tokens.module';
import { ConversationsModule } from './conversations/conversations.module';
import { RealtimeModule } from './realtime/realtime.module';
import { GlobalJwtGuard } from './auth/global-jwt.guard';
import { User } from './users/user.entity';
import { DeviceToken } from './device-tokens/device-token.entity';
import { Conversation } from './conversations/conversation.entity';
import { ConversationMember } from './conversations/conversation-member.entity';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, load: [configuration] }),
    TypeOrmModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        type: 'postgres',
        host: config.get<string>('db.host'),
        port: config.get<number>('db.port'),
        username: config.get<string>('db.user'),
        password: config.get<string>('db.password'),
        database: config.get<string>('db.name'),
        entities: [User, DeviceToken, Conversation, ConversationMember],
        synchronize: config.get<boolean>('db.synchronize'), // dev only — disable in prod, use migrations
        logging: false,
      }),
    }),
    AuthModule,
    UsersModule,
    DeviceTokensModule,
    ConversationsModule,
    RealtimeModule,
  ],
  providers: [
    { provide: APP_GUARD, useClass: GlobalJwtGuard },
  ],
})
export class AppModule {}