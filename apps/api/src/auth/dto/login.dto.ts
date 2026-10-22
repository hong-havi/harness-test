import { IsBoolean, IsOptional, IsString } from 'class-validator';

export class LoginDto {
  @IsString()
  userId!: string;

  @IsString()
  password!: string;

  @IsOptional()
  @IsBoolean()
  rememberMe?: boolean;
}
