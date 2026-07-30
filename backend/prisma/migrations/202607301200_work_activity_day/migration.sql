CREATE TABLE "WorkActivityDay" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "localDate" TEXT NOT NULL,
  "tenantId" TEXT,
  "desktopLoginAt" TIMESTAMP(3),
  "loginLatitude" DOUBLE PRECISION,
  "loginLongitude" DOUBLE PRECISION,
  "loginAddress" TEXT,
  "sessionId" TEXT,
  "workingSeconds" INTEGER NOT NULL DEFAULT 0,
  "lastHeartbeatAt" TIMESTAMP(3),
  "lastConfirmedAt" TIMESTAMP(3),
  "pausedAt" TIMESTAMP(3),
  "activityStatus" TEXT NOT NULL DEFAULT 'OFFLINE',
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL,

  CONSTRAINT "WorkActivityDay_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "WorkActivityDay_userId_localDate_key"
  ON "WorkActivityDay"("userId", "localDate");

CREATE INDEX "WorkActivityDay_localDate_idx"
  ON "WorkActivityDay"("localDate");

CREATE INDEX "WorkActivityDay_tenantId_localDate_idx"
  ON "WorkActivityDay"("tenantId", "localDate");

ALTER TABLE "WorkActivityDay"
  ADD CONSTRAINT "WorkActivityDay_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
