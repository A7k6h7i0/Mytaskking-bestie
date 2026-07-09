-- Allow self-registered organisations to await platform approval.
ALTER TYPE "TenantStatus" ADD VALUE IF NOT EXISTS 'PENDING';
