-- v1.10: Deck soft-delete (trash for 7 days)
ALTER TABLE decks ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ DEFAULT NULL;
