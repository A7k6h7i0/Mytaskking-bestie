-- Field HR ops: expenses, leaves, incidents, ratings, routes, daily plans

CREATE TABLE "FieldExpense" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "amount" DECIMAL(12,2) NOT NULL,
    "description" TEXT,
    "receiptUrl" TEXT,
    "expenseDate" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "approvedById" TEXT,
    "approvedAt" TIMESTAMP(3),
    "rejectionReason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "FieldExpense_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "FieldLeave" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "leaveType" TEXT NOT NULL,
    "fromDate" TEXT NOT NULL,
    "toDate" TEXT NOT NULL,
    "days" INTEGER NOT NULL DEFAULT 1,
    "reason" TEXT,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "approvedById" TEXT,
    "approvedAt" TIMESTAMP(3),
    "rejectionReason" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "FieldLeave_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "FieldHoliday" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "date" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "FieldHoliday_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "FieldIncident" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "location" TEXT,
    "mediaUrls" TEXT,
    "status" TEXT NOT NULL DEFAULT 'open',
    "resolvedById" TEXT,
    "resolvedAt" TIMESTAMP(3),
    "resolutionNotes" TEXT,
    "offlineId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "FieldIncident_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "FieldRating" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "entityType" TEXT NOT NULL,
    "entityId" TEXT NOT NULL,
    "score" INTEGER NOT NULL,
    "notes" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "FieldRating_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "FieldRoute" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "assignedToId" TEXT,
    "outletIds" JSONB NOT NULL DEFAULT '[]',
    "status" TEXT NOT NULL DEFAULT 'active',
    "createdById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "FieldRoute_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "FieldDailyPlan" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "routeId" TEXT,
    "planDate" TEXT NOT NULL,
    "outletIds" JSONB NOT NULL DEFAULT '[]',
    "notes" TEXT,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "createdById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "FieldDailyPlan_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "FieldExpense_tenantId_idx" ON "FieldExpense"("tenantId");
CREATE INDEX "FieldExpense_tenantId_userId_idx" ON "FieldExpense"("tenantId", "userId");
CREATE INDEX "FieldExpense_tenantId_status_idx" ON "FieldExpense"("tenantId", "status");
CREATE INDEX "FieldLeave_tenantId_idx" ON "FieldLeave"("tenantId");
CREATE INDEX "FieldLeave_tenantId_userId_idx" ON "FieldLeave"("tenantId", "userId");
CREATE INDEX "FieldHoliday_tenantId_idx" ON "FieldHoliday"("tenantId");
CREATE INDEX "FieldIncident_tenantId_idx" ON "FieldIncident"("tenantId");
CREATE INDEX "FieldIncident_tenantId_userId_idx" ON "FieldIncident"("tenantId", "userId");
CREATE INDEX "FieldRating_tenantId_entityType_entityId_idx" ON "FieldRating"("tenantId", "entityType", "entityId");
CREATE INDEX "FieldRoute_tenantId_idx" ON "FieldRoute"("tenantId");
CREATE INDEX "FieldRoute_tenantId_assignedToId_idx" ON "FieldRoute"("tenantId", "assignedToId");
CREATE INDEX "FieldDailyPlan_tenantId_idx" ON "FieldDailyPlan"("tenantId");
CREATE INDEX "FieldDailyPlan_tenantId_userId_planDate_idx" ON "FieldDailyPlan"("tenantId", "userId", "planDate");

ALTER TABLE "FieldExpense" ADD CONSTRAINT "FieldExpense_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "FieldLeave" ADD CONSTRAINT "FieldLeave_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "FieldIncident" ADD CONSTRAINT "FieldIncident_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "FieldRating" ADD CONSTRAINT "FieldRating_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "FieldRoute" ADD CONSTRAINT "FieldRoute_assignedToId_fkey" FOREIGN KEY ("assignedToId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "FieldRoute" ADD CONSTRAINT "FieldRoute_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "FieldDailyPlan" ADD CONSTRAINT "FieldDailyPlan_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "FieldDailyPlan" ADD CONSTRAINT "FieldDailyPlan_routeId_fkey" FOREIGN KEY ("routeId") REFERENCES "FieldRoute"("id") ON DELETE SET NULL ON UPDATE CASCADE;
