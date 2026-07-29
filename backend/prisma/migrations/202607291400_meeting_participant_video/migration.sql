-- Per-participant camera state for live meetings (survives rejoin).
ALTER TABLE "MeetingRoomParticipant" ADD COLUMN "videoEnabled" BOOLEAN NOT NULL DEFAULT false;
