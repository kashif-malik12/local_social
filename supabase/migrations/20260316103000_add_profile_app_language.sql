alter table public.profiles
add column if not exists app_language text not null default 'fr';

update public.profiles
set app_language = 'fr'
where app_language is null or app_language not in ('en', 'fr');

alter table public.profiles
drop constraint if exists profiles_app_language_check;

alter table public.profiles
add constraint profiles_app_language_check
check (app_language in ('en', 'fr'));
