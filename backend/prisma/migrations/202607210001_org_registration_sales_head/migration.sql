-- Org registration, subscription, SALES_HEAD role, admin notes

ALTER TYPE "Role" ADD VALUE IF NOT EXISTS 'SALES_HEAD';

CREATE TYPE "GovtIdType" AS ENUM ('AADHAAR', 'PAN', 'VOTER_ID', 'DRIVING_LICENSE');
CREATE TYPE "RegistrationReviewStatus" AS ENUM ('SUBMITTED', 'UNDER_REVIEW', 'APPROVED', 'REJECTED');
CREATE TYPE "SubscriptionStatus" AS ENUM ('NONE', 'TRIAL_REQUESTED', 'TRIAL_ACTIVE', 'PAYMENT_PENDING', 'PAID', 'EXPIRED');
CREATE TYPE "AdminNoteStatus" AS ENUM ('PENDING', 'APPROVED', 'REJECTED');

CREATE TABLE "TenantRegistration" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "adminPhone" TEXT NOT NULL,
    "adminEmail" TEXT NOT NULL,
    "emailVerifiedAt" TIMESTAMP(3),
    "govtId1Type" "GovtIdType" NOT NULL,
    "govtId1Number" TEXT NOT NULL,
    "govtId1ImageUrl" TEXT,
    "govtId2Type" "GovtIdType" NOT NULL,
    "govtId2Number" TEXT NOT NULL,
    "govtId2ImageUrl" TEXT,
    "reviewStatus" "RegistrationReviewStatus" NOT NULL DEFAULT 'SUBMITTED',
    "reviewedById" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "rejectReason" TEXT,
    "submittedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TenantRegistration_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "TenantSubscription" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "status" "SubscriptionStatus" NOT NULL DEFAULT 'NONE',
    "planMonths" INTEGER,
    "trialEndsAt" TIMESTAMP(3),
    "paidUntil" TIMESTAMP(3),
    "amountPaise" INTEGER,
    "currency" TEXT NOT NULL DEFAULT 'INR',
    "paymentProvider" TEXT,
    "paymentReference" TEXT,
    "razorpayOrderId" TEXT,
    "razorpayPaymentId" TEXT,
    "paidAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "TenantSubscription_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "EmailOtp" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "phone" TEXT,
    "codeHash" TEXT NOT NULL,
    "purpose" TEXT NOT NULL,
    "expiresAt" TIMESTAMP(3) NOT NULL,
    "verifiedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "EmailOtp_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "AdminNote" (
    "id" TEXT NOT NULL,
    "authorId" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "body" TEXT NOT NULL,
    "status" "AdminNoteStatus" NOT NULL DEFAULT 'PENDING',
    "reviewedById" TEXT,
    "reviewedAt" TIMESTAMP(3),
    "reviewNote" TEXT,
    "tenantId" TEXT NOT NULL DEFAULT 'default',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "AdminNote_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "TenantRegistration_tenantId_key" ON "TenantRegistration"("tenantId");
CREATE INDEX "TenantRegistration_reviewStatus_idx" ON "TenantRegistration"("reviewStatus");
CREATE UNIQUE INDEX "TenantSubscription_tenantId_key" ON "TenantSubscription"("tenantId");
CREATE INDEX "EmailOtp_email_purpose_idx" ON "EmailOtp"("email", "purpose");
CREATE INDEX "AdminNote_status_idx" ON "AdminNote"("status");
CREATE INDEX "AdminNote_tenantId_idx" ON "AdminNote"("tenantId");

ALTER TABLE "TenantRegistration" ADD CONSTRAINT "TenantRegistration_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "TenantRegistration" ADD CONSTRAINT "TenantRegistration_reviewedById_fkey" FOREIGN KEY ("reviewedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "TenantSubscription" ADD CONSTRAINT "TenantSubscription_tenantId_fkey" FOREIGN KEY ("tenantId") REFERENCES "Tenant"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "AdminNote" ADD CONSTRAINT "AdminNote_authorId_fkey" FOREIGN KEY ("authorId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "AdminNote" ADD CONSTRAINT "AdminNote_reviewedById_fkey" FOREIGN KEY ("reviewedById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
