import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import * as jwt from 'jsonwebtoken';
import { AuthService } from './auth.service';
import { jwtSecrets, JwtPayload } from './jwt-secrets';

export type { JwtPayload };

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(private readonly auth: AuthService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKeyProvider: (
        _request: unknown,
        rawJwtToken: string,
        done: (err: Error | null, secret?: string) => void,
      ) => {
        for (const secret of jwtSecrets()) {
          try {
            jwt.verify(rawJwtToken, secret);
            return done(null, secret);
          } catch {
            // try next
          }
        }
        done(null, jwtSecrets()[0]);
      },
    });
  }

  async validate(payload: JwtPayload) {
    const user = await this.auth.validatePayload(payload);
    if (!user) throw new UnauthorizedException();
    return { sub: user.id, username: user.username };
  }
}