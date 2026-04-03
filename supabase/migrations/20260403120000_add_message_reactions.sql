-- Direct chat message reactions (heart like)
CREATE TABLE IF NOT EXISTS message_reactions (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id uuid NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  emoji text NOT NULL DEFAULT '❤️',
  created_at timestamptz DEFAULT now(),
  UNIQUE(message_id, user_id)
);

ALTER TABLE message_reactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "message_reactions_select" ON message_reactions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM messages m
      JOIN conversations c ON c.id = m.conversation_id
      WHERE m.id = message_reactions.message_id
        AND (c.user1 = auth.uid() OR c.user2 = auth.uid())
    )
  );

CREATE POLICY "message_reactions_insert" ON message_reactions
  FOR INSERT WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM messages m
      JOIN conversations c ON c.id = m.conversation_id
      WHERE m.id = message_id
        AND (c.user1 = auth.uid() OR c.user2 = auth.uid())
    )
  );

CREATE POLICY "message_reactions_delete" ON message_reactions
  FOR DELETE USING (user_id = auth.uid());


-- Offer chat message reactions
CREATE TABLE IF NOT EXISTS offer_message_reactions (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id uuid NOT NULL REFERENCES offer_messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  emoji text NOT NULL DEFAULT '❤️',
  created_at timestamptz DEFAULT now(),
  UNIQUE(message_id, user_id)
);

ALTER TABLE offer_message_reactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "offer_message_reactions_select" ON offer_message_reactions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM offer_messages m
      JOIN offer_conversations c ON c.id = m.conversation_id
      WHERE m.id = offer_message_reactions.message_id
        AND (c.buyer_id = auth.uid() OR c.seller_id = auth.uid())
    )
  );

CREATE POLICY "offer_message_reactions_insert" ON offer_message_reactions
  FOR INSERT WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (
      SELECT 1 FROM offer_messages m
      JOIN offer_conversations c ON c.id = m.conversation_id
      WHERE m.id = message_id
        AND (c.buyer_id = auth.uid() OR c.seller_id = auth.uid())
    )
  );

CREATE POLICY "offer_message_reactions_delete" ON offer_message_reactions
  FOR DELETE USING (user_id = auth.uid());
