# Allonssy

Flutter app for the Allonssy community platform.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


## Supabase schema updates (required for Businesses + Food Ads)

If your DB still has an older `posts_post_type_check` (without `food_ad`) or no
`profiles.business_type` column, run:

- `supabase/2026-03-07-post-type-and-business-migration.sql`

This migration:
- adds `profiles.business_type`
- updates `posts_post_type_check` to include `food_ad`
