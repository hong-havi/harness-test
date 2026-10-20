import { ExecutionContext, ForbiddenException } from '@nestjs/common';
import { CsrfGuard } from './csrf.guard';

function makeCtx(cookie: string | undefined, header: string | undefined): ExecutionContext {
  const req = {
    cookies: cookie === undefined ? {} : { csrf_token: cookie },
    header: (name: string) => (name.toLowerCase() === 'x-csrf-token' ? header : undefined),
  };
  return {
    switchToHttp: () => ({ getRequest: () => req }),
  } as unknown as ExecutionContext;
}

describe('CsrfGuard', () => {
  const guard = new CsrfGuard();

  it('passes when cookie and header match', () => {
    expect(guard.canActivate(makeCtx('abc123', 'abc123'))).toBe(true);
  });

  it('rejects when header is missing', () => {
    expect(() => guard.canActivate(makeCtx('abc123', undefined))).toThrow(ForbiddenException);
  });

  it('rejects when cookie is missing', () => {
    expect(() => guard.canActivate(makeCtx(undefined, 'abc123'))).toThrow(ForbiddenException);
  });

  it('rejects when values differ', () => {
    expect(() => guard.canActivate(makeCtx('abc123', 'abc124'))).toThrow(ForbiddenException);
  });

  it('rejects when values differ in length', () => {
    expect(() => guard.canActivate(makeCtx('abc', 'abc1'))).toThrow(ForbiddenException);
  });
});
