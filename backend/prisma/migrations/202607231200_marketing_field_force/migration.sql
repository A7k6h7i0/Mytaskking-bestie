-- Field force / marketing merge: EXECUTIVE role + org-scoped SFA tables

ALTER TYPE "Role" ADD VALUE IF NOT EXISTS 'EXECUTIVE';

CREATE TABLE "MarketingOutlet" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "code" TEXT,
    "ownerName" TEXT,
    "phone" TEXT,
    "email" TEXT,
    "address" TEXT,
    "city" TEXT,
    "state" TEXT,
    "pincode" TEXT,
    "category" TEXT,
    "photoUrls" TEXT,
    "nextVisitDate" TIMESTAMP(3),
    "partyStatus" TEXT NOT NULL DEFAULT 'active',
    "source" TEXT NOT NULL DEFAULT 'manual',
    "latitude" DECIMAL(10,7),
    "longitude" DECIMAL(10,7),
    "grade" TEXT,
    "distributorId" TEXT,
    "regionId" TEXT,
    "territoryId" TEXT,
    "assignedToId" TEXT,
    "status" TEXT NOT NULL DEFAULT 'active',
    "approvalStatus" TEXT NOT NULL DEFAULT 'approved',
    "createdById" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "MarketingOutlet_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "FieldVisit" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "outletId" TEXT NOT NULL,
    "planId" TEXT,
    "checkInAt" TIMESTAMP(3),
    "checkOutAt" TIMESTAMP(3),
    "checkInLat" DECIMAL(10,7),
    "checkInLng" DECIMAL(10,7),
    "selfieUrl" TEXT,
    "notes" TEXT,
    "status" TEXT NOT NULL DEFAULT 'planned',
    "overrideReason" TEXT,
    "overrideApprovedBy" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "FieldVisit_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "FieldGpsLog" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "latitude" DECIMAL(10,7) NOT NULL,
    "longitude" DECIMAL(10,7) NOT NULL,
    "accuracy" DECIMAL(8,2),
    "speed" DECIMAL(8,2),
    "batteryLevel" INTEGER,
    "offlineId" TEXT,
    "loggedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "FieldGpsLog_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "MarketingCategory" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "parentId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "MarketingCategory_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "MarketingBrand" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "MarketingBrand_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "MarketingProduct" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "sku" TEXT,
    "name" TEXT NOT NULL,
    "categoryId" TEXT,
    "brandId" TEXT,
    "mrp" DECIMAL(12,2),
    "ptr" DECIMAL(12,2),
    "pts" DECIMAL(12,2),
    "gstPercent" DECIMAL(5,2),
    "uom" TEXT,
    "packSize" INTEGER,
    "stock" INTEGER NOT NULL DEFAULT 0,
    "availability" BOOLEAN NOT NULL DEFAULT true,
    "status" TEXT NOT NULL DEFAULT 'active',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "MarketingProduct_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "MarketingRegion" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "code" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "MarketingRegion_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "MarketingTerritory" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "regionId" TEXT,
    "name" TEXT NOT NULL,
    "description" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "MarketingTerritory_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "MarketingDistributor" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "phone" TEXT,
    "email" TEXT,
    "address" TEXT,
    "status" TEXT NOT NULL DEFAULT 'active',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "MarketingDistributor_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "FieldOrder" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "visitId" TEXT,
    "outletId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "distributorId" TEXT,
    "subtotal" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "discount" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "gst" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "total" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "paymentMode" TEXT,
    "creditDays" INTEGER,
    "outstandingBalance" DECIMAL(12,2),
    "notes" TEXT,
    "status" TEXT NOT NULL DEFAULT 'draft',
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "FieldOrder_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "FieldOrderItem" (
    "id" TEXT NOT NULL,
    "tenantId" TEXT NOT NULL,
    "orderId" TEXT NOT NULL,
    "productId" TEXT NOT NULL,
    "quantity" INTEGER NOT NULL,
    "freeQuantity" INTEGER NOT NULL DEFAULT 0,
    "mrp" DECIMAL(12,2),
    "ptr" DECIMAL(12,2),
    "discountPercent" DECIMAL(5,2) NOT NULL DEFAULT 0,
    "gstPercent" DECIMAL(5,2) NOT NULL DEFAULT 0,
    "lineTotal" DECIMAL(12,2),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "FieldOrderItem_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "MarketingOutlet_tenantId_idx" ON "MarketingOutlet"("tenantId");
CREATE INDEX "MarketingOutlet_tenantId_assignedToId_idx" ON "MarketingOutlet"("tenantId", "assignedToId");
CREATE INDEX "MarketingOutlet_tenantId_status_idx" ON "MarketingOutlet"("tenantId", "status");
CREATE INDEX "FieldVisit_tenantId_userId_idx" ON "FieldVisit"("tenantId", "userId");
CREATE INDEX "FieldVisit_outletId_idx" ON "FieldVisit"("outletId");
CREATE INDEX "FieldGpsLog_tenantId_userId_idx" ON "FieldGpsLog"("tenantId", "userId");
CREATE INDEX "FieldGpsLog_loggedAt_idx" ON "FieldGpsLog"("loggedAt");
CREATE INDEX "MarketingCategory_tenantId_idx" ON "MarketingCategory"("tenantId");
CREATE INDEX "MarketingBrand_tenantId_idx" ON "MarketingBrand"("tenantId");
CREATE INDEX "MarketingProduct_tenantId_idx" ON "MarketingProduct"("tenantId");
CREATE INDEX "MarketingProduct_tenantId_sku_idx" ON "MarketingProduct"("tenantId", "sku");
CREATE INDEX "MarketingRegion_tenantId_idx" ON "MarketingRegion"("tenantId");
CREATE INDEX "MarketingTerritory_tenantId_idx" ON "MarketingTerritory"("tenantId");
CREATE INDEX "MarketingDistributor_tenantId_idx" ON "MarketingDistributor"("tenantId");
CREATE INDEX "FieldOrder_tenantId_idx" ON "FieldOrder"("tenantId");
CREATE INDEX "FieldOrder_tenantId_userId_idx" ON "FieldOrder"("tenantId", "userId");
CREATE INDEX "FieldOrder_outletId_idx" ON "FieldOrder"("outletId");
CREATE INDEX "FieldOrderItem_orderId_idx" ON "FieldOrderItem"("orderId");

ALTER TABLE "MarketingOutlet" ADD CONSTRAINT "MarketingOutlet_assignedToId_fkey" FOREIGN KEY ("assignedToId") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "MarketingOutlet" ADD CONSTRAINT "MarketingOutlet_createdById_fkey" FOREIGN KEY ("createdById") REFERENCES "User"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "FieldVisit" ADD CONSTRAINT "FieldVisit_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "FieldVisit" ADD CONSTRAINT "FieldVisit_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "MarketingOutlet"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "FieldGpsLog" ADD CONSTRAINT "FieldGpsLog_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "MarketingProduct" ADD CONSTRAINT "MarketingProduct_categoryId_fkey" FOREIGN KEY ("categoryId") REFERENCES "MarketingCategory"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "MarketingProduct" ADD CONSTRAINT "MarketingProduct_brandId_fkey" FOREIGN KEY ("brandId") REFERENCES "MarketingBrand"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "MarketingTerritory" ADD CONSTRAINT "MarketingTerritory_regionId_fkey" FOREIGN KEY ("regionId") REFERENCES "MarketingRegion"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "FieldOrder" ADD CONSTRAINT "FieldOrder_visitId_fkey" FOREIGN KEY ("visitId") REFERENCES "FieldVisit"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "FieldOrder" ADD CONSTRAINT "FieldOrder_outletId_fkey" FOREIGN KEY ("outletId") REFERENCES "MarketingOutlet"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "FieldOrder" ADD CONSTRAINT "FieldOrder_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "FieldOrderItem" ADD CONSTRAINT "FieldOrderItem_orderId_fkey" FOREIGN KEY ("orderId") REFERENCES "FieldOrder"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "FieldOrderItem" ADD CONSTRAINT "FieldOrderItem_productId_fkey" FOREIGN KEY ("productId") REFERENCES "MarketingProduct"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
