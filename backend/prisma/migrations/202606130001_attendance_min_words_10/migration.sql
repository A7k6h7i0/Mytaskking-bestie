-- Production workspaces were seeded with minRequiredWords = 100 in WorkspaceSetting.
-- The product default is now 10; update the stored policy so mobile + web UIs match.
UPDATE "WorkspaceSetting"
SET value = '10'::jsonb, "updatedAt" = NOW()
WHERE scope = 'attendance' AND key = 'minRequiredWords';

INSERT INTO "WorkspaceSetting" ("id", "scope", "key", "value", "createdAt", "updatedAt")
SELECT
  'attendance_min_words_10',
  'attendance',
  'minRequiredWords',
  '10'::jsonb,
  NOW(),
  NOW()
WHERE NOT EXISTS (
  SELECT 1 FROM "WorkspaceSetting"
  WHERE scope = 'attendance' AND key = 'minRequiredWords'
);
