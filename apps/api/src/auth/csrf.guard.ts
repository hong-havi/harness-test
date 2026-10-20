import {
  CanActivate,
  ExecutionContext,
  ForbiddenException,
  Injectable,
} from '@nestjs/common';
import type { Request } from 'express';
import { timingSafeEqual } from 'crypto';

@Injectable()
export class CsrfGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const req = context.switchToHttp().getRequest<Request>();
    const cookieToken = req?.cookies?.['csrf_token'];
    const headerToken = req.header('x-csrf-token');

    if (
      typeof cookieToken !== 'string' ||
      typeof headerToken !== 'string' ||
      cookieToken.length === 0 ||
      headerToken.length === 0 ||
      cookieToken.length !== headerToken.length
    ) {
      throw new ForbiddenException('유효하지 않은 요청입니다.');
    }

    const a = Buffer.from(cookieToken, 'utf8');
    const b = Buffer.from(headerToken, 'utf8');
    if (!timingSafeEqual(a, b)) {
      throw new ForbiddenException('유효하지 않은 요청입니다.');
    }
    return true;
  }
}
