-- v1.7: Deck 系統 + AI chat + student ai_chat_enabled flag

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

-- students: add ai_chat_enabled flag (老師控制 per-student AI 功能)
ALTER TABLE students ADD COLUMN IF NOT EXISTS ai_chat_enabled BOOLEAN DEFAULT TRUE;

-- Disable RLS (this project uses token-based security via anon key)
ALTER TABLE decks         DISABLE ROW LEVEL SECURITY;
ALTER TABLE card_decks    DISABLE ROW LEVEL SECURITY;
ALTER TABLE card_ai_chats DISABLE ROW LEVEL SECURITY;

-- Grant access to anon role
GRANT ALL ON decks         TO anon;
GRANT ALL ON card_decks    TO anon;
GRANT ALL ON card_ai_chats TO anon;
-- v1.8: ai_chat_model_perm
ALTER TABLE students ADD COLUMN IF NOT EXISTS ai_chat_model_perm TEXT DEFAULT 'all';
