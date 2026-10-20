import 'reflect-metadata';
import { DataSource } from 'typeorm';
import { MemberEntity } from './members/member.entity';

export default new DataSource({
  type: 'mysql',
  host: process.env.DB_HOST ?? 'db',
  port: Number(process.env.DB_PORT ?? 3306),
  username: process.env.DB_USER ?? 'board',
  password: process.env.DB_PASSWORD ?? 'board_pw',
  database: process.env.DB_NAME ?? 'board',
  entities: [MemberEntity],
  migrations: ['src/migrations/*.ts'],
  synchronize: false,
  charset: 'utf8mb4',
  timezone: 'Z',
});
