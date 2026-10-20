import { MigrationInterface, QueryRunner } from 'typeorm';

export class CreateMembers1729468800000 implements MigrationInterface {
  name = 'CreateMembers1729468800000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE \`members\` (
        \`id\`            BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
        \`user_id\`       VARCHAR(32)     NOT NULL,
        \`password_hash\` VARCHAR(255)    NOT NULL,
        \`nickname\`      VARCHAR(32)     NOT NULL,
        \`created_at\`    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
        \`created_ip\`    VARCHAR(45)     NOT NULL,
        \`updated_at\`    DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP
                                                 ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (\`id\`),
        UNIQUE KEY \`uk_members_user_id\` (\`user_id\`),
        UNIQUE KEY \`uk_members_nickname\` (\`nickname\`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE \`members\`;`);
  }
}
