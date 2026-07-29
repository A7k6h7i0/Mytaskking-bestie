-- Add optional gender on employee/user profiles.
ALTER TABLE "User" ADD COLUMN IF NOT EXISTS "gender" TEXT;
