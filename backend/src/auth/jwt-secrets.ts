import * as jwt from 'jsonwebtoken';

export interface JwtPayload {
  sub: string;
  username: string;
}

/**
 * Secrets we accept. Historical tokens were signed with the code default
 * (`dev-secret-change-me`) when `.env` used invalid `KEY: value` syntax
 * that dotenv ignores. Docker / intended local env uses
 * `change-me-in-production-please`.
 */
export function jwtSecrets(): string[] {
  const list = [
    process.env.JWT_SECRET,
    'change-me-in-production-please',
    'dev-secret-change-me',
  ].filter((s): s is string => typeof s === 'string' && s.length > 0);
  return [...new Set(list)];
}

export function verifyAccessToken(token: string): JwtPayload | null {
  for (const secret of jwtSecrets()) {
    try {
      return jwt.verify(token, secret) as JwtPayload;
    } catch {
      // try the next known secret
    }
  }
  return null;
}

export function stripBearer(raw: string): string {
  return raw.startsWith('Bearer ') ? raw.slice(7) : raw;
}
