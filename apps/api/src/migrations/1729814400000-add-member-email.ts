import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddMemberEmail1729814400000 implements MigrationInterface {
  name = 'AddMemberEmail1729814400000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE \`members\`
        ADD COLUMN \`email\` VARCHAR(254) NULL DEFAULT NULL AFTER \`nickname\`;
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE \`members\` DROP COLUMN \`email\`;`);
  }
}
