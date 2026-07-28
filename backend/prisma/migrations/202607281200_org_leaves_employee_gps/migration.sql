-- Org-wide leave requests + employee GPS tracking (login activity)

CREATE TYPE "OrgLeaveType" AS ENUM ('FULL_DAY', 'HALF_DAY', 'PERMISSION');
CREATE TYPE "OrgLeaveStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED');

CREATE TABLE "OrgLeave" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "leaveType" "OrgLeaveType" NOT NULL,
    "fromDate" TEXT NOT NULL,
    "toDate" TEXT,
    "startTime" TEXT,
    "endTime" TEXT,
    "permissionHours" DOUBLE PRECISION,
    "description" TEXT NOT NULL,
    "status" "OrgLeaveStatus" NOT NULL DEFAULT 'PENDING',
    "approvedById" TEXT,
    "approvedAt" TIMESTAMP(3),
    "rejectionReason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "OrgLeave_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "EmployeeGpsLog" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "latitude" DECIMAL(10,7) NOT NULL,
    "longitude" DECIMAL(10,7) NOT NULL,
    "accuracy" DOUBLE PRECISION,
    "loggedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "EmployeeGpsLog_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "OrgLeave_tenantId_idx" ON "OrgLeave"("tenantId");
CREATE INDEX "OrgLeave_tenantId_userId_idx" ON "OrgLeave"("tenantId", "userId");
CREATE INDEX "OrgLeave_tenantId_status_idx" ON "OrgLeave"("tenantId", "status");
CREATE INDEX "EmployeeGpsLog_tenantId_userId_idx" ON "EmployeeGpsLog"("tenantId", "userId");
CREATE INDEX "EmployeeGpsLog_tenantId_loggedAt_idx" ON "EmployeeGpsLog"("tenantId", "loggedAt");

ALTER TABLE "OrgLeave" ADD CONSTRAINT "OrgLeave_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "EmployeeGpsLog" ADD CONSTRAINT "EmployeeGpsLog_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
