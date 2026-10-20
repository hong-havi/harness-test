import { IsString, Length, Matches, MaxLength, MinLength } from 'class-validator';

export class SignupDto {
  @IsString()
  @Matches(/^[A-Za-z0-9]{4,32}$/, {
    message: 'user_id는 영문/숫자 4~32자여야 합니다.',
  })
  userId!: string;

  @IsString()
  @MinLength(8)
  @MaxLength(72)
  @Matches(/[A-Za-z]/, { message: 'password는 영문을 포함해야 합니다.' })
  @Matches(/[0-9]/, { message: 'password는 숫자를 포함해야 합니다.' })
  password!: string;

  @IsString()
  @Length(2, 32)
  nickname!: string;
}
