-- Promote event lifecycle to first-class column.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'EventState') THEN
    CREATE TYPE "EventState" AS ENUM ('OPEN', 'CLOSED', 'CANCELED');
  END IF;
END $$;

ALTER TABLE "Event"
  ADD COLUMN IF NOT EXISTS "state" "EventState";

UPDATE "Event"
SET "state" = CASE
  WHEN UPPER(COALESCE("metadataJson"->>'event_state', '')) = 'CANCELED' THEN 'CANCELED'::"EventState"
  WHEN "endTime" IS NULL
       AND (
         UPPER(COALESCE("metadataJson"->>'event_state', '')) = 'OPEN'
         OR LOWER(COALESCE("metadataJson"->>'entry_mode', '')) = 'manual_start'
       ) THEN 'OPEN'::"EventState"
  ELSE 'CLOSED'::"EventState"
END
WHERE "state" IS NULL;

ALTER TABLE "Event"
  ALTER COLUMN "state" SET DEFAULT 'CLOSED'::"EventState",
  ALTER COLUMN "state" SET NOT NULL;

-- Resolve existing duplicate OPEN events deterministically before adding unique constraint.
WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY "babyId", type
      ORDER BY "startTime" DESC, "createdAt" DESC, id DESC
    ) AS rn
  FROM "Event"
  WHERE "state" = 'OPEN'::"EventState"
)
UPDATE "Event" e
SET
  "state" = 'CLOSED'::"EventState",
  "endTime" = COALESCE(e."endTime", e."startTime"),
  "metadataJson" = jsonb_set(
    COALESCE(e."metadataJson", '{}'::jsonb),
    '{event_state}',
    '"CLOSED"'::jsonb,
    true
  )
FROM ranked r
WHERE e.id = r.id
  AND r.rn > 1;

CREATE INDEX IF NOT EXISTS "Event_babyId_type_state_startTime_idx"
  ON "Event" ("babyId", type, "state", "startTime" DESC);

CREATE UNIQUE INDEX IF NOT EXISTS "Event_babyId_type_open_unique"
  ON "Event" ("babyId", type)
  WHERE "state" = 'OPEN'::"EventState";
