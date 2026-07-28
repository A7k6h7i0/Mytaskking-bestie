-- Support ticket multi-assignee junction table
CREATE TABLE "SupportTicketAssignee" (
    "id" TEXT NOT NULL,
    "ticketId" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "assignedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "assignedById" TEXT,

    CONSTRAINT "SupportTicketAssignee_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "SupportTicketAssignee_ticketId_userId_key" ON "SupportTicketAssignee"("ticketId", "userId");
CREATE INDEX "SupportTicketAssignee_ticketId_idx" ON "SupportTicketAssignee"("ticketId");
CREATE INDEX "SupportTicketAssignee_userId_idx" ON "SupportTicketAssignee"("userId");

ALTER TABLE "SupportTicketAssignee" ADD CONSTRAINT "SupportTicketAssignee_ticketId_fkey" FOREIGN KEY ("ticketId") REFERENCES "SupportTicket"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SupportTicketAssignee" ADD CONSTRAINT "SupportTicketAssignee_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

INSERT INTO "SupportTicketAssignee" ("id", "ticketId", "userId", "assignedAt", "assignedById")
SELECT
    'sta_' || "id",
    "id",
    "assigneeId",
    COALESCE("assignedAt", CURRENT_TIMESTAMP),
    "assignedById"
FROM "SupportTicket"
WHERE "assigneeId" IS NOT NULL;
