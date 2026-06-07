-- Validated call duration record (#7 Call timer validation).
ALTER TABLE "Call"
  ADD COLUMN IF NOT EXISTS "durationSeconds" INTEGER;
