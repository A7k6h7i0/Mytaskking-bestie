-- Task completion reports and one-response-per-recipient replies.
CREATE TABLE IF NOT EXISTS "TaskCompletionReport" (
  "id" TEXT NOT NULL,
  "taskId" TEXT NOT NULL,
  "authorId" TEXT NOT NULL,
  "assignmentId" TEXT,
  "body" TEXT NOT NULL,
  "wordCount" INTEGER NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "TaskCompletionReport_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "TaskReportRecipient" (
  "id" TEXT NOT NULL,
  "reportId" TEXT NOT NULL,
  "userId" TEXT NOT NULL,
  "responseBody" TEXT,
  "respondedAt" TIMESTAMP(3),
  "responseUpdatedAt" TIMESTAMP(3),
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "TaskReportRecipient_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "TaskCompletionReport_assignmentId_key" ON "TaskCompletionReport"("assignmentId");
CREATE INDEX IF NOT EXISTS "TaskCompletionReport_taskId_createdAt_idx" ON "TaskCompletionReport"("taskId", "createdAt");
CREATE INDEX IF NOT EXISTS "TaskCompletionReport_authorId_createdAt_idx" ON "TaskCompletionReport"("authorId", "createdAt");
CREATE UNIQUE INDEX IF NOT EXISTS "TaskReportRecipient_reportId_userId_key" ON "TaskReportRecipient"("reportId", "userId");
CREATE INDEX IF NOT EXISTS "TaskReportRecipient_userId_createdAt_idx" ON "TaskReportRecipient"("userId", "createdAt");

ALTER TABLE "TaskCompletionReport"
  ADD CONSTRAINT "TaskCompletionReport_taskId_fkey"
  FOREIGN KEY ("taskId") REFERENCES "Task"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "TaskCompletionReport"
  ADD CONSTRAINT "TaskCompletionReport_authorId_fkey"
  FOREIGN KEY ("authorId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "TaskCompletionReport"
  ADD CONSTRAINT "TaskCompletionReport_assignmentId_fkey"
  FOREIGN KEY ("assignmentId") REFERENCES "TaskAssignee"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "TaskReportRecipient"
  ADD CONSTRAINT "TaskReportRecipient_reportId_fkey"
  FOREIGN KEY ("reportId") REFERENCES "TaskCompletionReport"("id") ON DELETE CASCADE ON UPDATE CASCADE;

ALTER TABLE "TaskReportRecipient"
  ADD CONSTRAINT "TaskReportRecipient_userId_fkey"
  FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;