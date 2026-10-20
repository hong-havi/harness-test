import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { MemberEntity } from './members/member.entity';
import { AuthModule } from './auth/auth.module';
import { MembersModule } from './members/members.module';

@Module({
  imports: [
    TypeOrmModule.forRoot({
      type: 'mysql',
      host: process.env.DB_HOST ?? 'db',
      port: Number(process.env.DB_PORT ?? 3306),
      username: process.env.DB_USER ?? 'board',
      password: process.env.DB_PASSWORD ?? 'board_pw',
      database: process.env.DB_NAME ?? 'board',
      entities: [MemberEntity],
      migrations: ['dist/migrations/*.js'],
      synchronize: false,
      charset: 'utf8mb4',
      timezone: 'Z',
    }),
    AuthModule,
    MembersModule,
  ],
})
export class AppModule {}
