insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  last_sign_in_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  is_super_admin,
  is_sso_user,
  is_anonymous
) values
(
  '00000000-0000-0000-0000-000000000000',
  'af162817-7e8e-4efe-b57f-58b0ee210bb8',
  'authenticated',
  'authenticated',
  'ali.kashifmalik@gmail.com',
  '$2a$10$dQxYQ4shs6As3rjWfEuU.OdJnMcyuRGSZHP90FTOI8WgSgCgLt0JC',
  '2026-02-19 18:42:09.908787+00',
  '2026-03-12 15:12:37.147233+00',
  '{"provider": "email", "providers": ["email"]}'::jsonb,
  '{"sub": "af162817-7e8e-4efe-b57f-58b0ee210bb8", "email": "ali.kashifmalik@gmail.com", "app_settings": {"video_autoplay": false}, "feed_filters": {"gig_types": ["service_offer", "service_request"], "org_kinds": [], "org_enabled": false, "food_enabled": false, "gigs_enabled": true, "general_scope": "all", "gig_categories": ["marketing"], "market_enabled": true, "market_intents": ["buying", "selling"], "food_categories": ["indian"], "general_enabled": true, "lost_found_scope": "all", "market_categories": ["house_sale", "electronics"], "lost_found_enabled": true}, "email_verified": true, "phone_verified": false}'::jsonb,
  '2026-02-19 18:41:49.976939+00',
  '2026-03-13 13:18:53.649931+00',
  false,
  false,
  false
),
(
  '00000000-0000-0000-0000-000000000000',
  '7c7e8689-ef32-4840-9653-bde3fe126d43',
  'authenticated',
  'authenticated',
  'kashifmalik3250@gmail.com',
  '$2a$10$6P18IoLqP64CSoWbOe/SSu8o/xXB7wdqfL5qe1wpqbqsmq4rYTyb2',
  '2026-03-12 15:24:23.893232+00',
  '2026-03-12 15:24:25.887722+00',
  '{"provider": "email", "providers": ["email"]}'::jsonb,
  '{"sub": "7c7e8689-ef32-4840-9653-bde3fe126d43", "email": "kashifmalik3250@gmail.com", "feed_filters": {"gig_types": ["service_offer", "service_request"], "org_kinds": ["government", "news_agency"], "org_enabled": false, "food_enabled": false, "gigs_enabled": false, "general_scope": "all", "gig_categories": ["marketing", "finance", "business_services", "home_services", "tech", "design", "education"], "market_enabled": false, "market_intents": ["buying", "selling"], "food_categories": ["indian", "high_protein", "pizza", "burger", "pasta", "starters"], "general_enabled": true, "lost_found_scope": "all", "market_categories": ["mobile_phone", "house_sale", "house_rent", "computers", "bikes", "electronics", "fashion", "home_garden", "vehicles"], "lost_found_enabled": false}, "email_verified": true, "phone_verified": false}'::jsonb,
  '2026-03-12 15:23:28.497384+00',
  '2026-03-12 15:27:00.901451+00',
  false,
  false,
  false
)
on conflict (id) do nothing;

insert into auth.identities (
  provider_id,
  user_id,
  identity_data,
  provider,
  last_sign_in_at,
  created_at,
  updated_at,
  id
) values
(
  'af162817-7e8e-4efe-b57f-58b0ee210bb8',
  'af162817-7e8e-4efe-b57f-58b0ee210bb8',
  '{"sub": "af162817-7e8e-4efe-b57f-58b0ee210bb8", "email": "ali.kashifmalik@gmail.com", "email_verified": true, "phone_verified": false}'::jsonb,
  'email',
  '2026-02-19 18:41:50.086603+00',
  '2026-02-19 18:41:50.087301+00',
  '2026-02-19 18:41:50.087301+00',
  '2480ef88-a5a7-4240-ba2b-d192e733f8b9'
),
(
  '7c7e8689-ef32-4840-9653-bde3fe126d43',
  '7c7e8689-ef32-4840-9653-bde3fe126d43',
  '{"sub": "7c7e8689-ef32-4840-9653-bde3fe126d43", "email": "kashifmalik3250@gmail.com", "email_verified": false, "phone_verified": false}'::jsonb,
  'email',
  '2026-03-12 15:23:28.627559+00',
  '2026-03-12 15:23:28.628213+00',
  '2026-03-12 15:23:28.628213+00',
  '6923662e-620d-4ce1-a214-36adee8622d9'
)
on conflict (id) do nothing;
