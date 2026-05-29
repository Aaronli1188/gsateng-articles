-- gsatword Supabase schema
-- 在 Supabase Dashboard > SQL Editor 執行這個檔案

-- Enable UUID
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Students
CREATE TABLE IF NOT EXISTS students (
  id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name    TEXT UNIQUE NOT NULL,
  token   TEXT UNIQUE NOT NULL DEFAULT encode(gen_random_bytes(16), 'hex'),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Vocabulary
CREATE TABLE IF NOT EXISTS vocabulary (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id  UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  word        TEXT NOT NULL,
  first_seen  DATE,
  context     TEXT    DEFAULT '',
  zh_meaning  TEXT    DEFAULT '',
  context_zh  TEXT    DEFAULT '',
  mastered    BOOLEAN DEFAULT FALSE,
  next_review DATE,
  memo        TEXT    DEFAULT '',
  marked      BOOLEAN DEFAULT FALSE,
  UNIQUE(student_id, word)
);

-- Reviews
CREATE TABLE IF NOT EXISTS reviews (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vocab_id    UUID NOT NULL REFERENCES vocabulary(id) ON DELETE CASCADE,
  reviewed_at DATE NOT NULL,
  result      TEXT NOT NULL   -- 'y', 'n', 'too_easy'
);

-- Allow full access via anon key (this is a private system, security via token)
ALTER TABLE students   DISABLE ROW LEVEL SECURITY;
ALTER TABLE vocabulary DISABLE ROW LEVEL SECURITY;
ALTER TABLE reviews    DISABLE ROW LEVEL SECURITY;

-- Grant access to anon role
GRANT ALL ON students   TO anon;
GRANT ALL ON vocabulary TO anon;
GRANT ALL ON reviews    TO anon;
