import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { JwtAuthGuard } from './jwt-auth.guard';

export const IS_PUBLIC_KEY = 'isPublic';

/**
 * Global guard: protects every route with JWT auth, unless marked @Public().
 */
@Injectable()
export class GlobalJwtGuard implements CanActivate {
  constructor(private readonly reflector: Reflector, private readonly jwtGuard: JwtAuthGuard) {}

  async canActivate(context: ExecutionContext): Promise<boolean> {
    const isPublic = this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    if (isPublic) return true;
    return (await this.jwtGuard.canActivate(context)) as boolean;
  }
}