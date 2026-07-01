import { HttpException, HttpStatus, Injectable } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import * as bcrypt from 'bcrypt';
import { Repository } from 'typeorm';
import { User } from '../users/user.entity';
import { RegisterDto, LoginDto } from './dto';
import { DeviceTokensService } from '../device-tokens/device-tokens.service';

@Injectable()
export class AuthService {
  constructor(
    @InjectRepository(User) private readonly users: Repository<User>,
    private readonly jwt: JwtService,
    private readonly deviceTokens: DeviceTokensService,
  ) {}

  async register(dto: RegisterDto) {
    const username = dto.username.toLowerCase();
    const exists = await this.users.findOne({
      where: [{ username }, { email: dto.email.toLowerCase() }],
    });
    if (exists) {
      const field = exists.email === dto.email.toLowerCase() ? 'email' : 'username';
      throw new HttpException(`${field} already in use`, HttpStatus.CONFLICT);
    }

    const passwordHash = await bcrypt.hash(dto.password, 10);
    const user = this.users.create({
      username,
      fullName: dto.fullName,
      email: dto.email.toLowerCase(),
      passwordHash,
    });
    const saved = await this.users.save(user);
    return this.issueToken(saved);
  }

  async login(dto: LoginDto) {
    const user = await this.users
      .findOne({ where: [{ username: dto.login.toLowerCase() }, { email: dto.login.toLowerCase() }] })
      .then((u) =>
        u ? this.users.findOne({ where: { id: u.id }, select: ['id', 'username', 'passwordHash'] }) : null,
      );
    if (!user) throw new HttpException('Invalid credentials', HttpStatus.UNAUTHORIZED);

    const ok = await bcrypt.compare(dto.password, user.passwordHash);
    if (!ok) throw new HttpException('Invalid credentials', HttpStatus.UNAUTHORIZED);

    if (dto.fcmToken) {
      await this.deviceTokens.register(user.id, dto.fcmToken);
    }

    return this.issueToken(user);
  }

  private async issueToken(user: User) {
    const payload = { sub: user.id, username: user.username };
    const accessToken = await this.jwt.signAsync(payload);
    return {
      accessToken,
      user: { id: user.id, username: user.username },
    };
  }

  async validatePayload(payload: { sub: string; username: string }): Promise<User | null> {
    return this.users.findOne({ where: { id: payload.sub } });
  }
}