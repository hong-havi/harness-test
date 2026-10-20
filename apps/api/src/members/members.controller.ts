import {
  Body,
  Controller,
  Get,
  Patch,
  Req,
  UseGuards,
} from '@nestjs/common';
import type { Request } from 'express';
import { JwtAuthGuard } from '../auth/jwt-auth.guard';
import { CsrfGuard } from '../auth/csrf.guard';
import type { JwtPayload } from '../auth/jwt.strategy';
import { MembersService } from './members.service';
import { UpdateMeDto } from './dto/update-me.dto';

@Controller('members')
export class MembersController {
  constructor(private readonly membersService: MembersService) {}

  @Get('me')
  @UseGuards(JwtAuthGuard)
  async getMe(@Req() req: Request) {
    const user = req.user as JwtPayload;
    return this.membersService.getMe(user.sub);
  }

  @Patch('me')
  @UseGuards(JwtAuthGuard, CsrfGuard)
  async updateMe(@Req() req: Request, @Body() dto: UpdateMeDto) {
    const user = req.user as JwtPayload;
    return this.membersService.updateMe(user.sub, dto);
  }
}
