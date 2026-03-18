-- Add market_price_max column to support price ranges on marketplace and gigs posts.
ALTER TABLE posts ADD COLUMN IF NOT EXISTS market_price_max double precision;
