import { ConflictException, UnauthorizedException } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { Repository } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { AuthService } from './auth.service';
import { MemberEntity } from '../members/member.entity';

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

  describe('login', () => {
    it('returns tokens on success', async () => {
      const hash = await bcrypt.hash('password12', 10);
      (repo as any).__qb.getOne.mockResolvedValue({
        id: '7',
        userId: 'alice01',
        nickname: 'alice',
        passwordHash: hash,
      });

      const result = await service.login({ userId: 'alice01', password: 'password12' });

      expect(result.member).toEqual({ id: '7', userId: 'alice01', nickname: 'alice' });
      expect(result.accessToken).toBe('jwt.signed.value');
      expect(result.csrfToken).toMatch(/^[0-9a-f]{64}$/);
      expect(result.maxAgeSeconds).toBe(3600);
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
