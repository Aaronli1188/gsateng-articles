-- ── Enable RLS on all tables ─────────────────────────────────────────────────
ALTER TABLE students            ENABLE ROW LEVEL SECURITY;
ALTER TABLE vocabulary          ENABLE ROW LEVEL SECURITY;
ALTER TABLE reviews             ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_sessions    ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_usage            ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_config          ENABLE ROW LEVEL SECURITY;

-- ── students: student can only read their own row ─────────────────────────────
CREATE POLICY "student_read_own" ON students
  FOR SELECT TO anon
  USING (token = (current_setting('request.headers', true)::json->>'x-student-token'));

-- ── vocabulary: student can read/write own rows ───────────────────────────────
CREATE POLICY "student_vocab_all" ON vocabulary
  FOR ALL TO anon
  USING (student_id = (
    SELECT id FROM students
    WHERE token = (current_setting('request.headers', true)::json->>'x-student-token')
  ))
  WITH CHECK (student_id = (
    SELECT id FROM students
    WHERE token = (current_setting('request.headers', true)::json->>'x-student-token')
  ));

-- ── reviews: student can read/insert own reviews ──────────────────────────────
CREATE POLICY "student_reviews_all" ON reviews
  FOR ALL TO anon
  USING (vocab_id IN (
    SELECT v.id FROM vocabulary v
    JOIN students s ON s.id = v.student_id
    WHERE s.token = (current_setting('request.headers', true)::json->>'x-student-token')
  ))
  WITH CHECK (vocab_id IN (
    SELECT v.id FROM vocabulary v
    JOIN students s ON s.id = v.student_id
    WHERE s.token = (current_setting('request.headers', true)::json->>'x-student-token')
  ));

-- ── student_sessions: student can insert/read own ─────────────────────────────
CREATE POLICY "student_sessions_insert" ON student_sessions
  FOR INSERT TO anon
  WITH CHECK (student_id = (
    SELECT id FROM students
    WHERE token = (current_setting('request.headers', true)::json->>'x-student-token')
  ));

CREATE POLICY "student_sessions_read_own" ON student_sessions
  FOR SELECT TO anon
  USING (student_id = (
    SELECT id FROM students
    WHERE token = (current_setting('request.headers', true)::json->>'x-student-token')
  ));

-- ── ai_usage: student can insert own usage ────────────────────────────────────
CREATE POLICY "student_ai_usage_insert" ON ai_usage
  FOR INSERT TO anon
  WITH CHECK (student_id = (
    SELECT id FROM students
    WHERE token = (current_setting('request.headers', true)::json->>'x-student-token')
  ));

-- ── app_config: read-only for all anon ───────────────────────────────────────
CREATE POLICY "app_config_read" ON app_config
  FOR SELECT TO anon
  USING (true);
