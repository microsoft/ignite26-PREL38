-- Caldova learning operations schema and deterministic healthy seed.
-- Safe to run repeatedly: stable records use primary keys and upserts; generated workload
-- rows are inserted only when the target table is empty.

CREATE TABLE IF NOT EXISTS courses (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  discipline TEXT NOT NULL,
  units INTEGER NOT NULL CHECK (units > 0),
  enrolled INTEGER NOT NULL CHECK (enrolled >= 0)
);

CREATE TABLE IF NOT EXISTS learners (
  id TEXT PRIMARY KEY,
  display_name TEXT NOT NULL,
  email TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'active'
);

CREATE TABLE IF NOT EXISTS enrollments (
  learner_id TEXT NOT NULL REFERENCES learners(id),
  course_id TEXT NOT NULL REFERENCES courses(id),
  enrolled_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (learner_id, course_id)
);

CREATE TABLE IF NOT EXISTS assessments (
  id TEXT PRIMARY KEY,
  course_id TEXT NOT NULL REFERENCES courses(id),
  title TEXT NOT NULL,
  due_at TIMESTAMPTZ NOT NULL
);

CREATE TABLE IF NOT EXISTS quiz_questions (
  id BIGSERIAL PRIMARY KEY,
  assessment_id TEXT NOT NULL REFERENCES assessments(id),
  position INTEGER NOT NULL,
  prompt TEXT NOT NULL,
  options JSONB NOT NULL,
  answer_idx INTEGER NOT NULL,
  UNIQUE (assessment_id, position)
);

CREATE TABLE IF NOT EXISTS question_bank (
  id BIGSERIAL PRIMARY KEY,
  assessment_id TEXT NOT NULL,
  prompt TEXT NOT NULL,
  options JSONB NOT NULL,
  answer_idx INTEGER NOT NULL,
  active BOOLEAN NOT NULL DEFAULT true
);

CREATE INDEX IF NOT EXISTS idx_question_bank_assessment_active
  ON question_bank (assessment_id, prompt) WHERE active;

CREATE TABLE IF NOT EXISTS quiz_attempts (
  id BIGSERIAL PRIMARY KEY,
  assessment_id TEXT NOT NULL REFERENCES assessments(id),
  learner_id TEXT NOT NULL REFERENCES learners(id),
  total INTEGER NOT NULL,
  correct INTEGER NOT NULL,
  score_pct INTEGER NOT NULL CHECK (score_pct BETWEEN 0 AND 100),
  submitted_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_quiz_attempts_learner_submitted
  ON quiz_attempts (learner_id, submitted_at DESC);

CREATE TABLE IF NOT EXISTS reporting_exports (
  id BIGSERIAL PRIMARY KEY,
  status TEXT NOT NULL,
  row_count INTEGER NOT NULL DEFAULT 0,
  file_name TEXT NOT NULL,
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ
);

INSERT INTO courses (id, title, discipline, units, enrolled) VALUES
  ('OPS-201', 'Reliable Cloud Operations', 'Technology', 8, 184),
  ('DATA-215', 'Applied Data Analysis', 'Analytics', 10, 146),
  ('BUS-140', 'Responsible Business Decisions', 'Business', 6, 203)
ON CONFLICT (id) DO UPDATE SET
  title = EXCLUDED.title,
  discipline = EXCLUDED.discipline,
  units = EXCLUDED.units,
  enrolled = EXCLUDED.enrolled;

INSERT INTO learners (id, display_name, email, status) VALUES
  ('LRN-1001', 'Avery Morgan', 'avery.morgan@example.invalid', 'active'),
  ('LRN-1002', 'Jordan Lee', 'jordan.lee@example.invalid', 'active'),
  ('LRN-1003', 'Riley Chen', 'riley.chen@example.invalid', 'active'),
  ('LRN-1004', 'Cameron Patel', 'cameron.patel@example.invalid', 'active')
ON CONFLICT (id) DO UPDATE SET
  display_name = EXCLUDED.display_name,
  email = EXCLUDED.email,
  status = EXCLUDED.status;

INSERT INTO enrollments (learner_id, course_id) VALUES
  ('LRN-1001', 'OPS-201'), ('LRN-1001', 'DATA-215'),
  ('LRN-1002', 'OPS-201'), ('LRN-1002', 'BUS-140'),
  ('LRN-1003', 'DATA-215'), ('LRN-1003', 'BUS-140'),
  ('LRN-1004', 'OPS-201'), ('LRN-1004', 'DATA-215')
ON CONFLICT DO NOTHING;

INSERT INTO assessments (id, course_id, title, due_at) VALUES
  ('OPS-201-M1', 'OPS-201', 'Service health foundations', '2026-11-15T23:59:00Z'),
  ('DATA-215-M1', 'DATA-215', 'Interpreting operational data', '2026-11-18T23:59:00Z'),
  ('BUS-140-M1', 'BUS-140', 'Evidence-based decisions', '2026-11-20T23:59:00Z')
ON CONFLICT (id) DO UPDATE SET
  course_id = EXCLUDED.course_id,
  title = EXCLUDED.title,
  due_at = EXCLUDED.due_at;

INSERT INTO quiz_questions (assessment_id, position, prompt, options, answer_idx) VALUES
  ('OPS-201-M1', 1, 'Which signal most directly shows whether users can complete a request?', '["CPU model","Success rate","Resource group name","Image tag"]', 1),
  ('OPS-201-M1', 2, 'What should a health endpoint return when a required database is unavailable?', '["200","204","302","503"]', 3),
  ('OPS-201-M1', 3, 'Which practice reduces risk during a release?', '["Delete telemetry","Skip validation","Use a reversible rollout","Share credentials"]', 2),
  ('DATA-215-M1', 1, 'Which percentile highlights slow requests without focusing on one outlier?', '["p50","p95","minimum","count"]', 1),
  ('DATA-215-M1', 2, 'What is the safest way to parameterize a database query?', '["String concatenation","Prepared values","Shell expansion","URL encoding"]', 1),
  ('DATA-215-M1', 3, 'A useful baseline should be collected when the service is?', '["Healthy","Deleted","Unreachable","Unmonitored"]', 0),
  ('BUS-140-M1', 1, 'A durable operational decision should be supported by?', '["A single guess","Measured evidence","A hidden change","An expired token"]', 1),
  ('BUS-140-M1', 2, 'Which record explains why a production change was approved?', '["Change record","Browser cache","DNS suffix","Process ID"]', 0),
  ('BUS-140-M1', 3, 'What is a good first response to incomplete evidence?', '["Invent details","Gather more evidence","Delete logs","Disable alerts"]', 1)
ON CONFLICT (assessment_id, position) DO UPDATE SET
  prompt = EXCLUDED.prompt,
  options = EXCLUDED.options,
  answer_idx = EXCLUDED.answer_idx;

INSERT INTO question_bank (assessment_id, prompt, options, answer_idx, active)
SELECT
  (ARRAY['OPS-201-M1','DATA-215-M1','BUS-140-M1'])[1 + (series % 3)],
  'Caldova practice item ' || series,
  '["Option A","Option B","Option C","Option D"]'::jsonb,
  series % 4,
  true
FROM generate_series(1, 120000) AS series
WHERE NOT EXISTS (SELECT 1 FROM question_bank);

INSERT INTO quiz_attempts (assessment_id, learner_id, total, correct, score_pct, submitted_at)
SELECT * FROM (VALUES
  ('OPS-201-M1', 'LRN-1001', 3, 3, 100, '2026-10-01T16:00:00Z'::timestamptz),
  ('DATA-215-M1', 'LRN-1001', 3, 2, 67, '2026-10-02T17:15:00Z'::timestamptz),
  ('OPS-201-M1', 'LRN-1002', 3, 2, 67, '2026-10-03T14:30:00Z'::timestamptz),
  ('BUS-140-M1', 'LRN-1002', 3, 3, 100, '2026-10-04T18:20:00Z'::timestamptz),
  ('DATA-215-M1', 'LRN-1003', 3, 3, 100, '2026-10-05T15:40:00Z'::timestamptz),
  ('OPS-201-M1', 'LRN-1004', 3, 2, 67, '2026-10-06T19:05:00Z'::timestamptz)
) AS seed(assessment_id, learner_id, total, correct, score_pct, submitted_at)
WHERE NOT EXISTS (SELECT 1 FROM quiz_attempts);

INSERT INTO reporting_exports (status, row_count, file_name, started_at, completed_at)
SELECT 'completed', 6, 'caldova-grades-baseline.csv', '2026-10-06T20:00:00Z', '2026-10-06T20:00:04Z'
WHERE NOT EXISTS (SELECT 1 FROM reporting_exports);
