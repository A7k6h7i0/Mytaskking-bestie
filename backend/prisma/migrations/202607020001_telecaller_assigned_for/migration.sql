-- Date-wise telecaller lead assignment.
ALTER TABLE "Lead" ADD COLUMN "assignedFor" TIMESTAMP(3);

CREATE INDEX "Lead_ownerId_assignedFor_idx" ON "Lead"("ownerId", "assignedFor");
