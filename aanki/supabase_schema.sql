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

-- Decks (每個學生自己的牌組)
CREATE TABLE IF NOT EXISTS decks (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id  UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  name        TEXT NOT NULL,
  description TEXT DEFAULT '',
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Card-Deck junction (一張卡可屬於多個 Deck)
CREATE TABLE IF NOT EXISTS card_decks (
  card_id UUID NOT NULL REFERENCES vocabulary(id) ON DELETE CASCADE,
  deck_id UUID NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
  PRIMARY KEY (card_id, deck_id)
);

-- AI chat per card per student (持久對話紀錄)
CREATE TABLE IF NOT EXISTS card_ai_chats (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  card_id    UUID NOT NULL REFERENCES vocabulary(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  messages   JSONB NOT NULL DEFAULT '[]',
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(card_id, student_id)
);

-- Students: add ai_chat_enabled flag (老師控制 per-student AI 功能)
ALTER TABLE students ADD COLUMN IF NOT EXISTS ai_chat_enabled BOOLEAN DEFAULT TRUE;

-- Allow full access via anon key (this is a private system, security via token)
ALTER TABLE students      DISABLE ROW LEVEL SECURITY;
ALTER TABLE vocabulary    DISABLE ROW LEVEL SECURITY;
ALTER TABLE reviews       DISABLE ROW LEVEL SECURITY;
ALTER TABLE decks         DISABLE ROW LEVEL SECURITY;
ALTER TABLE card_decks    DISABLE ROW LEVEL SECURITY;
ALTER TABLE card_ai_chats DISABLE ROW LEVEL SECURITY;

-- Grant access to anon role
GRANT ALL ON students      TO anon;
GRANT ALL ON vocabulary    TO anon;
GRANT ALL ON reviews       TO anon;
GRANT ALL ON decks         TO anon;
GRANT ALL ON card_decks    TO anon;
GRANT ALL ON card_ai_chats TO anon;
