-- Coverage tracker auto-maintenance via AFTER INSERT triggers.
--
-- Migration 0007 created coverage_tracker but nothing populated it. This
-- migration wires three triggers (one per bucket table) that UPSERT the
-- per-(board,class,subject,chapter,topic,subtopic,question_type,difficulty)
-- rollup row whenever a question lands.
--
-- Trigger fires row-level on the partitioned parent (questions_master) and
-- on the two non-partitioned bucket tables. Postgres 13+ propagates the
-- row trigger automatically to all LIST partitions of questions_master.
--
-- Idempotent: ON CONFLICT updates the right counter and stamps last_updated.

-- ---- Trigger function ----

CREATE OR REPLACE FUNCTION coverage_tracker_upsert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  delta_good     INT := 0;
  delta_upgrade  INT := 0;
  delta_bad      INT := 0;
BEGIN
  -- TG_ARGV[0] is the bucket name we set on each CREATE TRIGGER below.
  IF TG_ARGV[0] = 'good' THEN
    delta_good := 1;
  ELSIF TG_ARGV[0] = 'upgrade' THEN
    delta_upgrade := 1;
  ELSIF TG_ARGV[0] = 'bad' THEN
    delta_bad := 1;
  END IF;

  INSERT INTO coverage_tracker (
    board, class, subject, chapter, topic, subtopic,
    question_type, difficulty,
    good_count, upgrade_count, bad_count, last_updated
  )
  VALUES (
    NEW.board, NEW.class, NEW.subject,
    COALESCE(NEW.chapter, ''), COALESCE(NEW.topic, ''), COALESCE(NEW.subtopic, ''),
    NEW.question_type, NEW.difficulty,
    delta_good, delta_upgrade, delta_bad, now()
  )
  ON CONFLICT (board, class, subject, chapter, topic, subtopic, question_type, difficulty)
  DO UPDATE SET
    good_count    = coverage_tracker.good_count    + EXCLUDED.good_count,
    upgrade_count = coverage_tracker.upgrade_count + EXCLUDED.upgrade_count,
    bad_count     = coverage_tracker.bad_count     + EXCLUDED.bad_count,
    last_updated  = now();

  RETURN NEW;
END;
$$;

-- ---- Triggers ----

DROP TRIGGER IF EXISTS trg_coverage_qm  ON questions_master;
CREATE TRIGGER trg_coverage_qm
AFTER INSERT ON questions_master
FOR EACH ROW
EXECUTE FUNCTION coverage_tracker_upsert('good');

DROP TRIGGER IF EXISTS trg_coverage_rq  ON review_queue;
CREATE TRIGGER trg_coverage_rq
AFTER INSERT ON review_queue
FOR EACH ROW
EXECUTE FUNCTION coverage_tracker_upsert('upgrade');

DROP TRIGGER IF EXISTS trg_coverage_rj  ON rejected_questions;
CREATE TRIGGER trg_coverage_rj
AFTER INSERT ON rejected_questions
FOR EACH ROW
EXECUTE FUNCTION coverage_tracker_upsert('bad');

-- ---- Rebuild procedure (for ops + post-migration repair) ----
--
-- If coverage_tracker ever drifts out of sync (manual deletes, restore from
-- backup, missed migration), run:
--   CALL coverage_tracker_rebuild();
-- Truncates + recomputes from authoritative bucket tables. Safe to re-run.

CREATE OR REPLACE PROCEDURE coverage_tracker_rebuild()
LANGUAGE plpgsql
AS $$
BEGIN
  TRUNCATE TABLE coverage_tracker;

  INSERT INTO coverage_tracker (
    board, class, subject, chapter, topic, subtopic, question_type, difficulty,
    good_count, upgrade_count, bad_count, last_updated
  )
  SELECT
    board, class, subject,
    COALESCE(chapter, '') AS chapter,
    COALESCE(topic, '')   AS topic,
    COALESCE(subtopic,'') AS subtopic,
    question_type, difficulty,
    SUM(good_delta)    AS good_count,
    SUM(upgrade_delta) AS upgrade_count,
    SUM(bad_delta)     AS bad_count,
    now()              AS last_updated
  FROM (
    SELECT board, class, subject, chapter, topic, subtopic, question_type, difficulty,
           1 AS good_delta, 0 AS upgrade_delta, 0 AS bad_delta
    FROM questions_master
    UNION ALL
    SELECT board, class, subject, chapter, topic, subtopic, question_type, difficulty,
           0, 1, 0
    FROM review_queue
    UNION ALL
    SELECT board, class, subject, chapter, topic, subtopic, question_type, difficulty,
           0, 0, 1
    FROM rejected_questions
  ) all_rows
  GROUP BY 1, 2, 3, 4, 5, 6, 7, 8;
END;
$$;

-- ---- Convenience view: gap analysis ----
--
-- Surfaces (board, class, subject, chapter, qtype, difficulty) combinations
-- where coverage is thin (< 5 good questions) so the ops team can prioritise
-- which submissions to backfill. Used by dashboards + the "next batch to
-- generate" picker.

CREATE OR REPLACE VIEW coverage_gaps AS
SELECT
  board, class, subject, chapter, topic, subtopic, question_type, difficulty,
  good_count, upgrade_count, bad_count,
  CASE
    WHEN good_count + upgrade_count + bad_count = 0 THEN 1.0
    ELSE good_count::numeric / NULLIF(good_count + upgrade_count + bad_count, 0)
  END AS good_ratio,
  last_updated
FROM coverage_tracker
WHERE good_count < 5
ORDER BY good_count ASC, last_updated ASC;
