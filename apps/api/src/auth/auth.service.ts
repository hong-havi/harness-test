import {
  BadRequestException,
  ConflictException,
  Injectable,
  UnauthorizedException,
} from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { InjectRepository } from '@nestjs/typeorm';
import { Repository, QueryFailedError } from 'typeorm';
import { randomBytes } from 'crypto';
import * as bcrypt from 'bcrypt';
import { MemberEntity } from '../members/member.entity';
import { SignupDto } from './dto/signup.dto';
import { LoginDto } from './dto/login.dto';
import { JoinDto } from './dto/join.dto';

const BCRYPT_SALT_ROUNDS = 10;
const DUP_ENTRY_CODE = 'ER_DUP_ENTRY';
const REMEMBER_ME_EXPIRES_SECONDS = 604800;
const NICKNAME_MAX_LENGTH = 32;
const NICKNAME_SUFFIX_LENGTH = 4;
const NICKNAME_MAX_ATTEMPTS = 5;
// bcrypt.hashSync('placeholder', 10) 로 생성한 valid 포맷 더미.
// 사용자가 없을 때도 bcrypt.compare 를 호출해 타이밍 차이를 줄인다.
const DUMMY_BCRYPT_HASH =
  '$2b$10$CwTycUXWue0Thq9StjUM0uJ8.Z3VvHZ8Vj6ynUhV6s3nxMVKPMMW.';

export interface PublicMember {
  id: string;
  userId: string;
  nickname: string;
}

export interface LoginResult {
  member: PublicMember;
  accessToken: string;
  csrfToken: string;
  // number > 0: 쿠키 Max-Age (초), null: session cookie (Max-Age 생략)
  maxAgeSeconds: number | null;
}

@Injectable()
export class AuthService {
  constructor(
    @InjectRepository(MemberEntity)
    private readonly membersRepo: Repository<MemberEntity>,
    private readonly jwtService: JwtService,
  ) {}

  async signup(dto: SignupDto, ip: string): Promise<PublicMember> {
    const [userIdDup, nickDup] = await Promise.all([
      this.membersRepo.exists({ where: { userId: dto.userId } }),
      this.membersRepo.exists({ where: { nickname: dto.nickname } }),
    ]);
    if (userIdDup) {
      throw new ConflictException('이미 사용 중인 아이디입니다.');
    }
    if (nickDup) {
      throw new ConflictException('이미 사용 중인 닉네임입니다.');
    }

    const passwordHash = await bcrypt.hash(dto.password, BCRYPT_SALT_ROUNDS);
    try {
      const saved = await this.membersRepo.save(
        this.membersRepo.create({
          userId: dto.userId,
          nickname: dto.nickname,
          passwordHash,
          createdIp: ip,
        }),
      );
      return { id: String(saved.id), userId: saved.userId, nickname: saved.nickname };
    } catch (e) {
      if (this.isDuplicateKey(e)) {
        throw new ConflictException(
          this.extractDupKey(e) === 'uk_members_nickname'
            ? '이미 사용 중인 닉네임입니다.'
            : '이미 사용 중인 아이디입니다.',
        );
      }
      throw e;
    }
  }

  async join(dto: JoinDto, ip: string): Promise<PublicMember> {
    const userIdDup = await this.membersRepo.exists({
      where: { userId: dto.userId },
    });
    if (userIdDup) {
      throw new ConflictException('이미 사용 중인 아이디입니다.');
    }

    const passwordHash = await bcrypt.hash(dto.password, BCRYPT_SALT_ROUNDS);

    // 닉네임 자동 생성: user_id 1차 시도 → 충돌 시 짧은 랜덤 접미사 재시도
    // UNIQUE 제약은 DB 레벨에서 걸려있으므로, 선검사 + save 에러 catch 를 모두 처리.
    let lastError: unknown;
    for (let attempt = 0; attempt < NICKNAME_MAX_ATTEMPTS; attempt++) {
      const nickname =
        attempt === 0
          ? this.truncateNickname(dto.userId)
          : this.buildNicknameWithSuffix(dto.userId);
      try {
        const saved = await this.membersRepo.save(
          this.membersRepo.create({
            userId: dto.userId,
            nickname,
            passwordHash,
            createdIp: ip,
          }),
        );
        return {
          id: String(saved.id),
          userId: saved.userId,
          nickname: saved.nickname,
        };
      } catch (e) {
        if (this.isDuplicateKey(e)) {
          const key = this.extractDupKey(e);
          if (key === 'uk_members_user_id' || key === 'user_id') {
            throw new ConflictException('이미 사용 중인 아이디입니다.');
          }
          // nickname 충돌 — 다음 접미사로 재시도
          lastError = e;
          continue;
        }
        throw e;
      }
    }
    throw new ConflictException(
      '닉네임 자동 생성에 실패했습니다. 잠시 후 다시 시도해 주세요.',
    );
  }

  private truncateNickname(base: string): string {
    return base.length > NICKNAME_MAX_LENGTH
      ? base.slice(0, NICKNAME_MAX_LENGTH)
      : base;
  }

  private buildNicknameWithSuffix(base: string): string {
    const suffix = randomBytes(NICKNAME_SUFFIX_LENGTH)
      .toString('hex')
      .slice(0, NICKNAME_SUFFIX_LENGTH);
    const reserved = suffix.length + 1; // '-' + suffix
    const headMax = NICKNAME_MAX_LENGTH - reserved;
    const head = base.length > headMax ? base.slice(0, headMax) : base;
    return `${head}-${suffix}`;
  }

  async login(dto: LoginDto): Promise<LoginResult> {
    const member = await this.membersRepo
      .createQueryBuilder('m')
      .addSelect('m.passwordHash')
      .where('m.user_id = :userId', { userId: dto.userId })
      .getOne();

    const invalid = new UnauthorizedException(
      '아이디 또는 비밀번호가 일치하지 않습니다.',
    );
    // 타이밍 공격 완화: user 유무와 무관하게 bcrypt.compare 1회 수행
    const hash = member?.passwordHash ?? DUMMY_BCRYPT_HASH;
    const ok = await bcrypt.compare(dto.password, hash);
    if (!member || !ok) {
      throw invalid;
    }

    const rememberMe = dto.rememberMe === true;
    const expiresIn = rememberMe
      ? REMEMBER_ME_EXPIRES_SECONDS
      : Number(process.env.JWT_EXPIRES_IN ?? 3600);
    const accessToken = await this.jwtService.signAsync(
      {
        sub: String(member.id),
        user_id: member.userId,
        nickname: member.nickname,
      },
      { expiresIn },
    );
    const csrfToken = randomBytes(32).toString('hex');

    return {
      member: {
        id: String(member.id),
        userId: member.userId,
        nickname: member.nickname,
      },
      accessToken,
      csrfToken,
      maxAgeSeconds: rememberMe ? REMEMBER_ME_EXPIRES_SECONDS : null,
    };
  }

  private isDuplicateKey(e: unknown): e is QueryFailedError & { code?: string } {
    return (
      e instanceof QueryFailedError &&
      typeof (e as unknown as { code?: string }).code === 'string' &&
      (e as unknown as { code: string }).code === DUP_ENTRY_CODE
    );
  }

  private extractDupKey(e: unknown): string | null {
    const msg =
      e instanceof Error && typeof (e as unknown as { message?: string }).message === 'string'
        ? (e as unknown as { message: string }).message
        : '';
    const match = msg.match(/for key '([^']+)'/);
    return match ? match[1].split('.').pop() ?? null : null;
  }
}
