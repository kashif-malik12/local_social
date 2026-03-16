# Supabase VPS Migration

This document is the working plan for moving `local_social` from hosted Supabase to a self-hosted Supabase deployment on the new VPS.

## Scope

Move these backend responsibilities to the VPS:

- Supabase Auth
- Postgres database
- Realtime
- Storage API and buckets
- PostgREST / REST API
- Edge Functions

Keep this out of scope for now:

- Push delivery infrastructure
  - Use Firebase/FCM later only for push notifications if needed.
- Media offloading to a second server/object storage
  - Keep media on the same stack first. Revisit after launch.

## Current Project Backend Inventory

Repo evidence as of March 13, 2026:

- Supabase migrations exist in [supabase/migrations](/C:/Users/ALI/Documents/VS%20Projects/local_social/supabase/migrations)
- Edge Functions exist in [supabase/functions/admin-delete-user](/C:/Users/ALI/Documents/VS%20Projects/local_social/supabase/functions/admin-delete-user) and [supabase/functions/admin-user-auth](/C:/Users/ALI/Documents/VS%20Projects/local_social/supabase/functions/admin-user-auth)
- Supabase local function config exists in [supabase/config.toml](/C:/Users/ALI/Documents/VS%20Projects/local_social/supabase/config.toml)
- Flutter app expects Supabase URL and anon key from [lib/core/config/env.dart](/C:/Users/ALI/Documents/VS%20Projects/local_social/lib/core/config/env.dart)

Expected app-level backend assets from the current codebase and project notes:

- Tables:
  - `profiles`
  - `posts`
  - `comments`
  - `reactions`
  - `conversations`
  - `messages`
  - `follows`
  - `blocks`
  - `reports`
  - notification-related tables/functions
- Storage buckets:
  - `avatars`
  - `post-images`
- SQL/RPC/functions used by the app:
  - `search_profiles`
  - `search_profiles_nearby`
  - `search_posts_scoped`
  - `search_posts_nearby_scoped`
  - `nearby_posts_city`
  - mention/share/admin notification functions

## Target VPS Layout

Use one VPS for now:

- `Ubuntu Server 24.04 LTS`
- Docker Engine + Docker Compose plugin
- Reverse proxy
  - Prefer `Caddy` for simpler TLS, or `Nginx` if you want stricter control
- Self-hosted Supabase stack
- Flutter web static hosting

Suggested domains:

- `app.example.com`
  - Flutter web
- `db.example.com` or `supabase.example.com`
  - Supabase API surface via reverse proxy

## Recommended Migration Order

1. Provision the VPS.
2. Harden the server.
3. Install Docker.
4. Deploy self-hosted Supabase.
5. Restore schema and database logic.
6. Create storage buckets and policies.
7. Deploy Edge Functions.
8. Point Flutter app env to the new Supabase URL and keys.
9. Run end-to-end app tests.
10. Only then treat the VPS stack as launch-ready.

## Phase 1: VPS Provisioning

Choose:

- OS: `Ubuntu Server 24.04 LTS`
- SSH key login enabled
- No GUI / minimal image
- Static public IPv4 if available

Record immediately after provisioning:

- VPS public IP
- SSH username
- domain names/subdomains
- DNS provider

## Phase 2: Base Server Hardening

Do this before deploying Supabase:

- Create a non-root sudo user
- Disable password SSH login if key login is working
- Set timezone
- Enable automatic security updates
- Configure firewall
  - allow `22`, `80`, `443`
  - do not expose Postgres directly unless you have a strong reason
- Install fail2ban if desired

## Phase 3: Docker Runtime

Install:

- Docker Engine
- Docker Compose plugin

Verify:

- `docker version`
- `docker compose version`

## Phase 4: Self-Hosted Supabase Deployment

Use Supabase's Docker-based self-hosting layout as the base.

What to prepare:

- a deployment directory on the VPS
- `.env` values for Supabase services
- JWT secrets
- DB passwords
- dashboard/studio credentials

Important:

- Keep all secrets out of git.
- Back up the final `.env` securely.
- Do not reuse weak development secrets in production.

## Phase 5: Database Migration

This repo already contains migration files in [supabase/migrations](/C:/Users/ALI/Documents/VS%20Projects/local_social/supabase/migrations).

Migration goal:

- replay all schema changes on the new Postgres instance
- verify tables, columns, constraints, indexes, RLS policies, triggers, and SQL functions exist

Checklist:

- apply all files from `supabase/migrations`
- verify older standalone SQL files in [supabase](/C:/Users/ALI/Documents/VS%20Projects/local_social/supabase) are either already represented in migrations or intentionally obsolete
- verify:
  - notification dedupe functions
  - admin moderation changes
  - offer chat changes
  - feed filter columns
  - block visibility rules

## Phase 6: Storage Migration

Minimum buckets expected:

- `avatars`
- `post-images`

Tasks:

- create buckets
- recreate bucket policies
- test public URL generation
- test upload from Flutter app
- test delete/cleanup flows for admin delete-user paths

Since the app is still in testing, media migration is simpler:

- either migrate test media
- or start with empty buckets and re-upload during testing

## Phase 7: Edge Functions

Deploy and verify:

- `admin-user-auth`
- `admin-delete-user`

From the repo:

- [supabase/functions/admin-user-auth/index.ts](/C:/Users/ALI/Documents/VS%20Projects/local_social/supabase/functions/admin-user-auth/index.ts)
- [supabase/functions/admin-delete-user/index.ts](/C:/Users/ALI/Documents/VS%20Projects/local_social/supabase/functions/admin-delete-user/index.ts)

Function checks:

- environment variables are set in the VPS deployment
- auth behavior matches current hosted project
- admin flows still work from the app

## Phase 8: Flutter App Cutover

Update app environment values in:

- [lib/core/config/env.dart](/C:/Users/ALI/Documents/VS%20Projects/local_social/lib/core/config/env.dart)

You will need:

- new Supabase URL
- new anon key
- any changed function URLs if directly referenced

Then test:

- register/login/logout
- profile completion
- create post with photo
- create post with video
- quick photo/video post
- comments/reactions
- chat
- follow / block / report flows
- admin flows

## Phase 9: Web Hosting

Host Flutter web on the same VPS for now.

Suggested setup:

- reverse proxy serves Flutter web static files on `app.example.com`
- Supabase API is routed on `supabase.example.com`

Keep the first deployment simple. Split web/media later only if required.

## Phase 10: Backups

Backups are mandatory before launch.

Set up:

- scheduled Postgres backups
- storage backup strategy
- restore test

Do not consider the migration complete until restore has been tested.

## Immediate Next Actions

When the VPS is ready, do these first:

1. Install `Ubuntu Server 24.04 LTS`
2. Add SSH key access
3. Point two subdomains
   - one for web
   - one for Supabase API
4. Harden server and install Docker
5. Pull the self-hosted Supabase stack onto the VPS

## Open Decisions

These still need a concrete decision during execution:

- reverse proxy choice
  - `Caddy` or `Nginx`
- whether to migrate existing test media or start fresh
- whether Flutter web and Supabase will share one domain with path routing or use separate subdomains
- where backups are stored
  - same VPS is not enough

## Working Rule

Do not change the app's production env to the VPS until all of these pass on the new stack:

- auth
- storage upload
- realtime
- Edge Functions
- main post flows
- quick media post flows
