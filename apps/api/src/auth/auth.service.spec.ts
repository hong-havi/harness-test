import { ConflictException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { QueryFailedError, Repository } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { AuthService } from './auth.service';
import { MemberEntity } from '../members/member.entity';

function makeDupError(key: string): QueryFailedError {
  const err = new QueryFailedError(
    'INSERT',
    [],
    new Error(
      `ER_DUP_ENTRY: Duplicate entry 'x' for key 'members.${key}'`,
    ),
  );
  (err as unknown as { code: string }).code = 'ER_DUP_ENTRY';
  (err as unknown as { message: string }).message =
    `ER_DUP_ENTRY: Duplicate entry 'x' for key 'members.${key}'`;
  return err;
}

type Mocked<T> = { [K in keyof T]: jest.Mock };

function makeRepo(): Mocked<Repository<MemberEntity>> {
  const qb = {
    addSelect: jest.fn().mockReturnThis(),
    where: jest.fn().mockReturnThis(),
    getOne: jest.fn(),
  };
  return {
    exists: jest.fn(),
    save: jest.fn(),
    create: jest.fn((data) => data),
    createQueryBuilder: jest.fn(() => qb),
    __qb: qb,
  } as unknown as Mocked<Repository<MemberEntity>>;
}

describe('AuthService', () => {
  let repo: ReturnType<typeof makeRepo>;
  let jwt: jest.Mocked<JwtService>;
  let service: AuthService;

  beforeEach(() => {
    process.env.JWT_EXPIRES_IN = '3600';
    repo = makeRepo();
    jwt = { signAsync: jest.fn().mockResolvedValue('jwt.signed.value') } as unknown as jest.Mocked<JwtService>;
    service = new AuthService(repo as unknown as Repository<MemberEntity>, jwt);
  });

  describe('signup', () => {
    it('creates member and returns public view', async () => {
      (repo.exists as jest.Mock).mockResolvedValueOnce(false).mockResolvedValueOnce(false);
      (repo.save as jest.Mock).mockResolvedValue({
        id: '1',
        userId: 'alice01',
        nickname: 'alice',
        passwordHash: 'hash',
      });

      const result = await service.signup(
        { userId: 'alice01', password: 'password12', nickname: 'alice' },
        '10.1.2.3',
      );

      expect(result).toEqual({ id: '1', userId: 'alice01', nickname: 'alice' });
      const savedArg = (repo.save as jest.Mock).mock.calls[0][0];
      expect(savedArg.createdIp).toBe('10.1.2.3');
      expect(savedArg.passwordHash).not.toBe('password12');
      expect(savedArg.passwordHash.startsWith('$2')).toBe(true);
    });

    it('throws 409 when user_id exists', async () => {
      (repo.exists as jest.Mock).mockResolvedValueOnce(true).mockResolvedValueOnce(false);
      await expect(
        service.signup(
          { userId: 'dup', password: 'password12', nickname: 'alice' },
          '1.1.1.1',
        ),
      ).rejects.toBeInstanceOf(ConflictException);
    });

    it('throws 409 when nickname exists', async () => {
      (repo.exists as jest.Mock).mockResolvedValueOnce(false).mockResolvedValueOnce(true);
      await expect(
        service.signup(
          { userId: 'alice01', password: 'password12', nickname: 'dup' },
          '1.1.1.1',
        ),
      ).rejects.toBeInstanceOf(ConflictException);
    });
  });

  describe('join', () => {
    it('creates member with nickname = userId on first attempt', async () => {
      (repo.exists as jest.Mock).mockResolvedValueOnce(false);
      (repo.save as jest.Mock).mockImplementation(async (data) => ({
        id: '42',
        ...data,
      }));

      const result = await service.join(
        { userId: 'joiner01', password: 'Abcd1234' },
        '10.1.2.3',
      );

      expect(result).toEqual({ id: '42', userId: 'joiner01', nickname: 'joiner01' });
      const savedArg = (repo.save as jest.Mock).mock.calls[0][0];
      expect(savedArg.nickname).toBe('joiner01');
      expect(savedArg.createdIp).toBe('10.1.2.3');
      expect(savedArg.passwordHash).not.toBe('Abcd1234');
      expect(savedArg.passwordHash.startsWith('$2')).toBe(true);
    });

    it('throws 409 when user_id already exists (pre-check)', async () => {
      (repo.exists as jest.Mock).mockResolvedValueOnce(true);
      await expect(
        service.join({ userId: 'dup', password: 'Abcd1234' }, '1.1.1.1'),
      ).rejects.toBeInstanceOf(ConflictException);
      expect(repo.save).not.toHaveBeenCalled();
    });

    it('retries with suffix on nickname collision then succeeds', async () => {
      (repo.exists as jest.Mock).mockResolvedValueOnce(false);
      (repo.save as jest.Mock)
        .mockRejectedValueOnce(makeDupError('uk_members_nickname'))
        .mockImplementationOnce(async (data) => ({ id: '7', ...data }));

      const result = await service.join(
        { userId: 'joiner01', password: 'Abcd1234' },
        '1.1.1.1',
      );

      expect(result.userId).toBe('joiner01');
      expect(result.nickname).toMatch(/^joiner01-[0-9a-f]{4}$/);
      expect((repo.save as jest.Mock).mock.calls.length).toBe(2);
    });

    it('maps race-condition user_id duplicate to 409', async () => {
      (repo.exists as jest.Mock).mockResolvedValueOnce(false);
      (repo.save as jest.Mock).mockRejectedValueOnce(
        makeDupError('uk_members_user_id'),
      );
      await expect(
        service.join({ userId: 'joiner01', password: 'Abcd1234' }, '1.1.1.1'),
      ).rejects.toBeInstanceOf(ConflictException);
    });

    it('throws 409 when nickname cannot be generated after max attempts', async () => {
      (repo.exists as jest.Mock).mockResolvedValueOnce(false);
      (repo.save as jest.Mock).mockRejectedValue(
        makeDupError('uk_members_nickname'),
      );
      await expect(
        service.join({ userId: 'joiner01', password: 'Abcd1234' }, '1.1.1.1'),
      ).rejects.toBeInstanceOf(ConflictException);
      expect((repo.save as jest.Mock).mock.calls.length).toBe(5);
    });

    it('truncates long userId to fit 32-char nickname limit', async () => {
      (repo.exists as jest.Mock).mockResolvedValueOnce(false);
      (repo.save as jest.Mock).mockImplementation(async (data) => ({
        id: '1',
        ...data,
      }));
      const longId = 'a'.repeat(32);

      const result = await service.join(
        { userId: longId, password: 'Abcd1234' },
        '1.1.1.1',
      );

      expect(result.nickname.length).toBeLessThanOrEqual(32);
      expect(result.nickname).toBe(longId);
    });
  });

  describe('login', () => {
    async function seedLoginMember() {
      const hash = await bcrypt.hash('password12', 10);
      (repo as any).__qb.getOne.mockResolvedValue({
        id: '7',
        userId: 'alice01',
        nickname: 'alice',
        passwordHash: hash,
      });
    }

    it('returns tokens on success (no rememberMe → session cookie)', async () => {
      await seedLoginMember();

      const result = await service.login({ userId: 'alice01', password: 'password12' });

      expect(result.member).toEqual({ id: '7', userId: 'alice01', nickname: 'alice' });
      expect(result.accessToken).toBe('jwt.signed.value');
      expect(result.csrfToken).toMatch(/^[0-9a-f]{64}$/);
      expect(result.maxAgeSeconds).toBeNull();
      expect(jwt.signAsync).toHaveBeenCalledWith(
        { sub: '7', user_id: 'alice01', nickname: 'alice' },
        { expiresIn: 3600 },
      );
    });

    it('rememberMe=true → maxAgeSeconds=604800 and JWT expiresIn=604800', async () => {
      await seedLoginMember();

      const result = await service.login({
        userId: 'alice01',
        password: 'password12',
        rememberMe: true,
      });

      expect(result.maxAgeSeconds).toBe(604800);
      expect(jwt.signAsync).toHaveBeenCalledWith(
        { sub: '7', user_id: 'alice01', nickname: 'alice' },
        { expiresIn: 604800 },
      );
    });

    it('rememberMe=false → session cookie, JWT expiresIn from env (3600)', async () => {
      await seedLoginMember();

      const result = await service.login({
        userId: 'alice01',
        password: 'password12',
        rememberMe: false,
      });

      expect(result.maxAgeSeconds).toBeNull();
      expect(jwt.signAsync).toHaveBeenCalledWith(
        { sub: '7', user_id: 'alice01', nickname: 'alice' },
        { expiresIn: 3600 },
      );
    });

    it('rememberMe=undefined behaves same as false (regression)', async () => {
      await seedLoginMember();

      const result = await service.login({
        userId: 'alice01',
        password: 'password12',
      });

      expect(result.maxAgeSeconds).toBeNull();
      expect(jwt.signAsync).toHaveBeenCalledWith(
        { sub: '7', user_id: 'alice01', nickname: 'alice' },
        { expiresIn: 3600 },
      );
    });

    it('throws 401 with generic message when user not found', async () => {
      (repo as any).__qb.getOne.mockResolvedValue(null);
      await expect(
        service.login({ userId: 'nobody', password: 'password12' }),
      ).rejects.toMatchObject({
        constructor: UnauthorizedException,
        message: '아이디 또는 비밀번호가 일치하지 않습니다.',
      });
    });

    it('throws 401 with generic message when password mismatch', async () => {
      const hash = await bcrypt.hash('password12', 10);
      (repo as any).__qb.getOne.mockResolvedValue({
        id: '7',
        userId: 'alice01',
        nickname: 'alice',
        passwordHash: hash,
      });

      await expect(
        service.login({ userId: 'alice01', password: 'wrong-password-9' }),
      ).rejects.toMatchObject({
        constructor: UnauthorizedException,
        message: '아이디 또는 비밀번호가 일치하지 않습니다.',
      });
    });
  });
});
