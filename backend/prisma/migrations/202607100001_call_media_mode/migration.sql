-- Persist voice vs video on calls so chat CALL_EVENT bubbles show the right type.
CREATE TYPE "CallMediaMode" AS ENUM ('VOICE', 'VIDEO');

ALTER TABLE "Call" ADD COLUMN "mode" "CallMediaMode" NOT NULL DEFAULT 'VIDEO';
