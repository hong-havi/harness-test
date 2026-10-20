import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { Not, Repository, QueryFailedError } from 'typeorm';
import * as bcrypt from 'bcrypt';
import { MemberEntity } from './member.entity';
import { UpdateMeDto } from './dto/update-me.dto';

const BCRYPT_SALT_ROUNDS = 10;
const DUP_ENTRY_CODE = 'ER_DUP_ENTRY';

export interface MeView {
  id: string;
  userId: string;
  nickname: string;
  createdAt: Date;
  updatedAt: Date;
}

@Injectable()
export class MembersService {
  constructor(
    @InjectRepository(MemberEntity)
    private readonly membersRepo: Repository<MemberEntity>,
  ) {}

  async getMe(id: string): Promise<MeView> {
    const member = await this.membersRepo.findOne({ where: { id } });
    if (!member) {
      throw new NotFoundException('회원을 찾을 수 없습니다.');
    }
    return this.toView(member);
  }

  async updateMe(id: string, dto: UpdateMeDto): Promise<MeView> {
    const hasNickname = dto.nickname !== undefined;
    const hasPassword = dto.newPassword !== undefined;
    if (!hasNickname && !hasPassword) {
      throw new BadRequestException('수정할 항목이 없습니다.');
    }

    if (hasNickname) {
      const dup = await this.membersRepo.exists({
        where: { nickname: dto.nickname!, id: Not(id) },
      });
      if (dup) {
        throw new ConflictException('이미 사용 중인 닉네임입니다.');
      }
    }

    if (hasPassword) {
      const withHash = await this.membersRepo
        .createQueryBuilder('m')
        .addSelect('m.passwordHash')
        .where('m.id = :id', { id })
        .getOne();
      if (!withHash) {
        throw new NotFoundException('회원을 찾을 수 없습니다.');
      }
      const ok = await bcrypt.compare(dto.currentPassword ?? '', withHash.passwordHash);
      if (!ok) {
        throw new BadRequestException('현재 비밀번호가 일치하지 않습니다.');
      }
    }

    const patch: Partial<MemberEntity> = {};
    if (hasNickname) patch.nickname = dto.nickname;
    if (hasPassword) patch.passwordHash = await bcrypt.hash(dto.newPassword!, BCRYPT_SALT_ROUNDS);

    try {
      await this.membersRepo.update({ id }, patch);
    } catch (e) {
      if (
        e instanceof QueryFailedError &&
        (e as unknown as { code?: string }).code === DUP_ENTRY_CODE
      ) {
        throw new ConflictException('이미 사용 중인 닉네임입니다.');
      }
      throw e;
    }

    return this.getMe(id);
  }

  private toView(m: MemberEntity): MeView {
    return {
      id: String(m.id),
      userId: m.userId,
      nickname: m.nickname,
      createdAt: m.createdAt,
      updatedAt: m.updatedAt,
    };
  }
}
