import {
  IsOptional,
  IsString,
  Length,
  Matches,
  MaxLength,
  MinLength,
  ValidateIf,
} from 'class-validator';

export class UpdateMeDto {
  @IsOptional()
  @IsString()
  @Length(2, 32)
  nickname?: string;

  @IsOptional()
  @IsString()
  @MinLength(8)
  @MaxLength(72)
  @Matches(/[A-Za-z]/, { message: 'newPassword는 영문을 포함해야 합니다.' })
  @Matches(/[0-9]/, { message: 'newPassword는 숫자를 포함해야 합니다.' })
  newPassword?: string;

  @ValidateIf((o: UpdateMeDto) => o.newPassword !== undefined)
  @IsString({ message: 'currentPassword가 필요합니다.' })
  currentPassword?: string;
}
