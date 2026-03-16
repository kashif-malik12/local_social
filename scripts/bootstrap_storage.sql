insert into storage.buckets (id, name, public)
values
  ('avatars', 'avatars', true),
  ('post-images', 'post-images', true),
  ('portfolio-images', 'portfolio-images', true)
on conflict (id) do update
set public = excluded.public;

drop policy if exists "Public read avatars" on storage.objects;
create policy "Public read avatars"
on storage.objects
for select
to public
using (bucket_id = 'avatars');

drop policy if exists "Public read post images" on storage.objects;
create policy "Public read post images"
on storage.objects
for select
to public
using (bucket_id = 'post-images');

drop policy if exists "Public read portfolio images" on storage.objects;
create policy "Public read portfolio images"
on storage.objects
for select
to public
using (bucket_id = 'portfolio-images');

drop policy if exists "Authenticated upload avatars" on storage.objects;
create policy "Authenticated upload avatars"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Authenticated upload post images" on storage.objects;
create policy "Authenticated upload post images"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'post-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Authenticated upload portfolio images" on storage.objects;
create policy "Authenticated upload portfolio images"
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'portfolio-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Authenticated update own avatars" on storage.objects;
create policy "Authenticated update own avatars"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Authenticated update own post images" on storage.objects;
create policy "Authenticated update own post images"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'post-images'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'post-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Authenticated update own portfolio images" on storage.objects;
create policy "Authenticated update own portfolio images"
on storage.objects
for update
to authenticated
using (
  bucket_id = 'portfolio-images'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'portfolio-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Authenticated delete own avatars" on storage.objects;
create policy "Authenticated delete own avatars"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Authenticated delete own post images" on storage.objects;
create policy "Authenticated delete own post images"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'post-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Authenticated delete own portfolio images" on storage.objects;
create policy "Authenticated delete own portfolio images"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'portfolio-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);
