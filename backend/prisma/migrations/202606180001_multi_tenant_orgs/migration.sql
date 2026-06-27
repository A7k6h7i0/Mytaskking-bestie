-- Lark-style multi-tenant organisations: default tenant + per-org user ids.

-- Ensure platform default tenant exists (MyTaskKing / Lakshmiraj main org).
INSERT INTO "Tenant" ("id", "slug", "name", "status", "createdAt", "updatedAt")
VALUES ('default', 'default', 'MyTaskKing', 'ACTIVE', NOW(), NOW())
ON CONFLICT ("id") DO NOTHING;

-- Backfill tenantId on all existing rows.
UPDATE "User" SET "tenantId" = 'default' WHERE "tenantId" IS NULL;
UPDATE "Channel" SET "tenantId" = 'default' WHERE "tenantId" IS NULL;
UPDATE "Task" SET "tenantId" = 'default' WHERE "tenantId" IS NULL;
UPDATE "Lead" SET "tenantId" = 'default' WHERE "tenantId" IS NULL;
UPDATE "FileAsset" SET "tenantId" = 'default' WHERE "tenantId" IS NULL;
UPDATE "MeetingRoom" SET "tenantId" = 'default' WHERE "tenantId" IS NULL;
UPDATE "Department" SET "tenantId" = 'default' WHERE "tenantId" IS NULL;

-- Call tenantId from initiator.
ALTER TABLE "Call" ADD COLUMN IF NOT EXISTS "tenantId" TEXT;
UPDATE "Call" c
SET "tenantId" = u."tenantId"
FROM "User" u
WHERE c."initiatorId" = u."id" AND c."tenantId" IS NULL;
CREATE INDEX IF NOT EXISTS "Call_tenantId_idx" ON "Call"("tenantId");

-- Tenant status column.
DO $$ BEGIN
  CREATE TYPE "TenantStatus" AS ENUM ('ACTIVE', 'SUSPENDED');
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE "Tenant" ADD COLUMN IF NOT EXISTS "status" "TenantStatus" NOT NULL DEFAULT 'ACTIVE';

-- User: login id unique per organisation (not globally).
DROP INDEX IF EXISTS "User_userId_key";
CREATE UNIQUE INDEX IF NOT EXISTS "User_tenantId_userId_key" ON "User"("tenantId", "userId");

-- Department names unique per organisation.
DROP INDEX IF EXISTS "Department_name_key";
CREATE UNIQUE INDEX IF NOT EXISTS "Department_tenantId_name_key" ON "Department"("tenantId", "name");
CREATE INDEX IF NOT EXISTS "Department_tenantId_idx" ON "Department"("tenantId");

-- User.tenantId defaults for new signups.
ALTER TABLE "User" ALTER COLUMN "tenantId" SET DEFAULT 'default';
ALTER TABLE "Department" ALTER COLUMN "tenantId" SET DEFAULT 'default';

-- Foreign key User → Tenant (idempotent).
DO $$ BEGIN
  ALTER TABLE "User"
    ADD CONSTRAINT "User_tenantId_fkey"
    FOREIGN KEY ("tenantId") REFERENCES "Tenant"("id")
    ON DELETE RESTRICT ON UPDATE CASCADE;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;
