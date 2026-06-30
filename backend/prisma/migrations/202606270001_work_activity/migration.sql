-- Work activity clips captured by visible desktop clients.
CREATE TABLE "WorkActivityClip" (
  "id" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "fileId" TEXT,
  "clipUrl" TEXT,
  "note" TEXT NOT NULL DEFAULT 'working',
  "status" TEXT NOT NULL DEFAULT 'WORKING',
  "platform" TEXT NOT NULL,
  "deviceLabel" TEXT,
  "durationSeconds" INTEGER NOT NULL DEFAULT 5,
  "captureStartedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "captureEndedAt" TIMESTAMP(3),
  "promptShownAt" TIMESTAMP(3),
  "promptRespondedAt" TIMESTAMP(3),
  "tenantId" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "WorkActivityClip_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "WorkActivityClip_userId_captureStartedAt_idx"
  ON "WorkActivityClip"("userId", "captureStartedAt");

CREATE INDEX "WorkActivityClip_tenantId_captureStartedAt_idx"
  ON "WorkActivityClip"("tenantId", "captureStartedAt");

CREATE INDEX "WorkActivityClip_status_idx"
  ON "WorkActivityClip"("status");

ALTER TABLE "WorkActivityClip"
  ADD CONSTRAINT "WorkActivityClip_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
