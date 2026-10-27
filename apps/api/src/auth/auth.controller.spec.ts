import type { Response } from 'express';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';

type CookieCall = { name: string; value: string; options: Record<string, unknown> };

function makeRes(): { res: Response; calls: CookieCall[] } {
  const calls: CookieCall[] = [];
  const res = {
    cookie(name: string, value: string, options: Record<string, unknown>) {
      calls.push({ name, value, options });
      return this;
    },
  } as unknown as Response;
  return { res, calls };
}

describe('AuthController.logout', () => {
  // logout 은 AuthService 를 사용하지 않고 쿠키 만료만 수행한다.
  const controller = new AuthController({} as AuthService);

  afterEach(() => {
    delete process.env.COOKIE_SECURE;
  });

  it('returns { ok: true }', async () => {
    const { res } = makeRes();
    await expect(controller.logout(res)).resolves.toEqual({ ok: true });
  });

  it('expires access_token cookie with Max-Age=0 and HttpOnly', async () => {
    const { res, calls } = makeRes();
    await controller.logout(res);

    const access = calls.find((c) => c.name === 'access_token');
    expect(access).toBeDefined();
    expect(access!.value).toBe('');
    expect(access!.options.maxAge).toBe(0);
    expect(access!.options.httpOnly).toBe(true);
    expect(access!.options.path).toBe('/');
    expect(access!.options.sameSite).toBe('lax');
  });

  it('expires csrf_token cookie with Max-Age=0 and not HttpOnly', async () => {
    const { res, calls } = makeRes();
    await controller.logout(res);

    const csrf = calls.find((c) => c.name === 'csrf_token');
    expect(csrf).toBeDefined();
    expect(csrf!.value).toBe('');
    expect(csrf!.options.maxAge).toBe(0);
    expect(csrf!.options.httpOnly).toBe(false);
    expect(csrf!.options.path).toBe('/');
    expect(csrf!.options.sameSite).toBe('lax');
  });

  it('marks both cookies Secure when COOKIE_SECURE=true (symmetry with login)', async () => {
    process.env.COOKIE_SECURE = 'true';
    const { res, calls } = makeRes();
    await controller.logout(res);

    const access = calls.find((c) => c.name === 'access_token');
    const csrf = calls.find((c) => c.name === 'csrf_token');
    expect(access!.options.secure).toBe(true);
    expect(csrf!.options.secure).toBe(true);
  });

  it('does not set Secure when COOKIE_SECURE is unset', async () => {
    const { res, calls } = makeRes();
    await controller.logout(res);

    const access = calls.find((c) => c.name === 'access_token');
    const csrf = calls.find((c) => c.name === 'csrf_token');
    expect(access!.options.secure).toBe(false);
    expect(csrf!.options.secure).toBe(false);
  });
});
