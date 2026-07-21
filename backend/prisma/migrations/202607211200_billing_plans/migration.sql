-- Dynamic billing plans managed by super admin

CREATE TABLE "BillingPlan" (
    "id" TEXT NOT NULL,
    "months" INTEGER NOT NULL,
    "label" TEXT NOT NULL,
    "amountPaise" INTEGER NOT NULL,
    "currency" TEXT NOT NULL DEFAULT 'INR',
    "isActive" BOOLEAN NOT NULL DEFAULT true,
    "sortOrder" INTEGER NOT NULL DEFAULT 0,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "BillingPlan_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "BillingPlan_isActive_sortOrder_idx" ON "BillingPlan"("isActive", "sortOrder");

ALTER TABLE "TenantSubscription" ADD COLUMN "planId" TEXT;

ALTER TABLE "TenantSubscription" ADD CONSTRAINT "TenantSubscription_planId_fkey"
    FOREIGN KEY ("planId") REFERENCES "BillingPlan"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- Seed default plans (matches previous env defaults)
INSERT INTO "BillingPlan" ("id", "months", "label", "amountPaise", "currency", "isActive", "sortOrder", "updatedAt")
VALUES
    ('plan_1m_default', 1, '1 month', 99900, 'INR', true, 1, CURRENT_TIMESTAMP),
    ('plan_6m_default', 6, '6 months', 499900, 'INR', true, 2, CURRENT_TIMESTAMP),
    ('plan_12m_default', 12, '12 months', 899900, 'INR', true, 3, CURRENT_TIMESTAMP);
