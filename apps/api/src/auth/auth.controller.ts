import {
  Body,
  Controller,
  HttpCode,
  Post,
  Req,
  Res,
  UseGuards,
} from '@nestjs/common';
import type { Request, Response } from 'express';
import { AuthService } from './auth.service';
import { SignupDto } from './dto/signup.dto';
import { LoginDto } from './dto/login.dto';
import { JwtAuthGuard } from './jwt-auth.guard';

const COOKIE_PATH = '/';

function cookieOptions(maxAgeMs: number | 0) {
  const secure = process.env.COOKIE_SECURE === 'true';
  return {
    path: COOKIE_PATH,
    sameSite: 'lax' as const,
    secure,
    maxAge: maxAgeMs,
  };
}

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Post('signup')
  async signup(@Body() dto: SignupDto, @Req() req: Request) {
    return this.authService.signup(dto, req.ip ?? '0.0.0.0');
  }

  @Post('login')
  @HttpCode(200)
  async login(
    @Body() dto: LoginDto,
    @Res({ passthrough: true }) res: Response,
  ) {
    const result = await this.authService.login(dto);
    const maxAgeMs = result.maxAgeSeconds * 1000;
    res.cookie('access_token', result.accessToken, {
      ...cookieOptions(maxAgeMs),
      httpOnly: true,
    });
    res.cookie('csrf_token', result.csrfToken, {
      ...cookieOptions(maxAgeMs),
      httpOnly: false,
    });
    return result.member;
  }

  @Post('logout')
  @HttpCode(200)
  @UseGuards(JwtAuthGuard)
  async logout(@Res({ passthrough: true }) res: Response) {
    res.cookie('access_token', '', { ...cookieOptions(0), httpOnly: true });
    res.cookie('csrf_token', '', { ...cookieOptions(0), httpOnly: false });
    return { ok: true };
  }
}
