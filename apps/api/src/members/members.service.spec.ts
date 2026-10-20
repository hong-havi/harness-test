import { BadRequestException, ConflictException } from '@nestjs/common';
import { Repository } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { MembersService } from './members.service';
import { MemberEntity } from './member.entity';

type Mocked<T> = { [K in keyof T]: jest.Mock };

function makeRepo(): Mocked<Repository<MemberEntity>> {
  const qb = {
    addSelect: jest.fn().mockReturnThis(),
    where: jest.fn().mockReturnThis(),
    getOne: jest.fn(),
  };
  return {
    exists: jest.fn(),
    findOne: jest.fn(),
    update: jest.fn().mockResolvedValue({ affected: 1 }),
    createQueryBuilder: jest.fn(() => qb),
    __qb: qb,
  } as unknown as Mocked<Repository<MemberEntity>>;
}

describe('MembersService', () => {
  let repo: ReturnType<typeof makeRepo>;
  let service: MembersService;

  beforeEach(() => {
    repo = makeRepo();
    service = new MembersService(repo as unknown as Repository<MemberEntity>);
  });

  describe('getMe', () => {
    it('returns me view without password_hash/created_ip', async () => {
      (repo.findOne as jest.Mock).mockResolvedValue({
        id: '1',
        userId: 'alice01',
        nickname: 'alice',
        createdAt: new Date('2026-10-20T00:00:00Z'),
        updatedAt: new Date('2026-10-20T00:00:00Z'),
      });

      const result = await service.getMe('1');

      expect(result).toEqual({
        id: '1',
        userId: 'alice01',
        nickname: 'alice',
        createdAt: new Date('2026-10-20T00:00:00Z'),
        updatedAt: new Date('2026-10-20T00:00:00Z'),
      });
      expect(result).not.toHaveProperty('passwordHash');
      expect(result).not.toHaveProperty('createdIp');
    });
  });

  describe('updateMe', () => {
    it('rejects empty body with 400', async () => {
      await expect(service.updateMe('1', {})).rejects.toBeInstanceOf(BadRequestException);
    });

    it('rejects duplicate nickname with 409', async () => {
      (repo.exists as jest.Mock).mockResolvedValue(true);
      await expect(
        service.updateMe('1', { nickname: 'taken' }),
      ).rejects.toBeInstanceOf(ConflictException);
    });

    it('updates nickname when free', async () => {
      (repo.exists as jest.Mock).mockResolvedValue(false);
      (repo.findOne as jest.Mock).mockResolvedValue({
        id: '1',
        userId: 'alice01',
        nickname: 'newnick',
        createdAt: new Date(),
        updatedAt: new Date(),
      });

      const result = await service.updateMe('1', { nickname: 'newnick' });

      expect(repo.update).toHaveBeenCalledWith({ id: '1' }, { nickname: 'newnick' });
      expect(result.nickname).toBe('newnick');
    });

    it('rejects password change with wrong currentPassword (400)', async () => {
      const hash = await bcrypt.hash('right-password-1', 10);
      (repo as any).__qb.getOne.mockResolvedValue({ id: '1', passwordHash: hash });

      await expect(
        service.updateMe('1', {
          newPassword: 'brand-new-9',
          currentPassword: 'wrong-password-9',
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
    });

    it('updates password with correct currentPassword', async () => {
      const hash = await bcrypt.hash('right-password-1', 10);
      (repo as any).__qb.getOne.mockResolvedValue({ id: '1', passwordHash: hash });
      (repo.findOne as jest.Mock).mockResolvedValue({
        id: '1',
        userId: 'alice01',
        nickname: 'alice',
        createdAt: new Date(),
        updatedAt: new Date(),
      });

      await service.updateMe('1', {
        newPassword: 'brand-new-9',
        currentPassword: 'right-password-1',
      });

      expect(repo.update).toHaveBeenCalledTimes(1);
      const patch = (repo.update as jest.Mock).mock.calls[0][1];
      expect(patch.passwordHash).toBeDefined();
      expect(patch.passwordHash.startsWith('$2')).toBe(true);
    });
  });
});
