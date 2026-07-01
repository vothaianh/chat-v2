import { SetMetadata } from '@nestjs/common';
import { IS_PUBLIC_KEY } from './global-jwt.guard';

/** Mark a route as not requiring authentication. */
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);