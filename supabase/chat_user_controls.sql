create table if not exists public.user_blocks (
  id uuid primary key default gen_random_uuid(),
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint user_blocks_unique unique (blocker_id, blocked_id),
  constraint user_blocks_self_check check (blocker_id <> blocked_id)
);

create index if not exists user_blocks_blocker_idx
  on public.user_blocks(blocker_id);

create index if not exists user_blocks_blocked_idx
  on public.user_blocks(blocked_id);

alter table public.user_blocks enable row level security;

drop policy if exists user_blocks_select_own on public.user_blocks;
create policy user_blocks_select_own
on public.user_blocks
for select
to authenticated
using (auth.uid() = blocker_id);

drop policy if exists user_blocks_insert_own on public.user_blocks;
create policy user_blocks_insert_own
on public.user_blocks
for insert
to authenticated
with check (auth.uid() = blocker_id);

drop policy if exists user_blocks_delete_own on public.user_blocks;
create policy user_blocks_delete_own
on public.user_blocks
for delete
to authenticated
using (auth.uid() = blocker_id);

with ranked as (
  select
    c.id,
    first_value(c.id) over (
      partition by least(c.user1, c.user2), greatest(c.user1, c.user2)
      order by c.created_at asc nulls last, c.id asc
    ) as keep_id
  from public.conversations c
)
update public.messages m
set conversation_id = ranked.keep_id
from ranked
where m.conversation_id = ranked.id
  and ranked.id <> ranked.keep_id;

with ranked as (
  select
    c.id,
    first_value(c.id) over (
      partition by least(c.user1, c.user2), greatest(c.user1, c.user2)
      order by c.created_at asc nulls last, c.id asc
    ) as keep_id
  from public.conversations c
)
delete from public.conversations c
using ranked
where c.id = ranked.id
  and ranked.id <> ranked.keep_id;

create unique index if not exists conversations_user_pair_unique
  on public.conversations (
    least(user1, user2),
    greatest(user1, user2)
  );

create or replace function public.get_or_create_conversation(
  p_other_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_a uuid;
  v_b uuid;
  v_conv_id uuid;
begin
  if v_me is null then
    raise exception 'Not authenticated';
  end if;

  if p_other_user_id is null or p_other_user_id = v_me then
    raise exception 'Invalid chat target';
  end if;

  if exists (
    select 1
    from public.user_blocks ub
    where (ub.blocker_id = v_me and ub.blocked_id = p_other_user_id)
       or (ub.blocker_id = p_other_user_id and ub.blocked_id = v_me)
  ) then
    raise exception 'Chat unavailable';
  end if;

  v_a := least(v_me, p_other_user_id);
  v_b := greatest(v_me, p_other_user_id);

  select c.id
  into v_conv_id
  from public.conversations c
  where c.user1 = v_a
    and c.user2 = v_b
  limit 1;

  if v_conv_id is not null then
    return v_conv_id;
  end if;

  begin
    insert into public.conversations (user1, user2)
    values (v_a, v_b)
    returning id into v_conv_id;
  exception
    when unique_violation then
      select c.id
      into v_conv_id
      from public.conversations c
      where c.user1 = v_a
        and c.user2 = v_b
      limit 1;
  end;

  return v_conv_id;
end;
$$;

create or replace function public.get_or_create_offer_conversation(
  p_post_id uuid,
  p_other_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_me uuid := auth.uid();
  v_post record;
  v_conv_id uuid;
begin
  if v_me is null then
    raise exception 'Not authenticated';
  end if;

  if exists (
    select 1
    from public.user_blocks ub
    where (ub.blocker_id = v_me and ub.blocked_id = p_other_user_id)
       or (ub.blocker_id = p_other_user_id and ub.blocked_id = v_me)
  ) then
    raise exception 'Offer chat unavailable';
  end if;

  select p.id, p.user_id, p.post_type
  into v_post
  from public.posts p
  where p.id = p_post_id
    and p.post_type in ('market', 'service_offer', 'service_request');

  if not found then
    raise exception 'Listing not found';
  end if;

  if v_post.user_id = v_me then
    raise exception 'You cannot start an offer chat on your own listing';
  end if;

  if v_post.user_id <> p_other_user_id then
    raise exception 'Offer chats must target the listing owner';
  end if;

  insert into public.offer_conversations (post_id, buyer_id, seller_id)
  values (p_post_id, v_me, v_post.user_id)
  on conflict (post_id, buyer_id, seller_id) do update
    set updated_at = now()
  returning id into v_conv_id;

  return v_conv_id;
end;
$$;

create or replace function public.delete_direct_conversation(
  p_conversation_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if not exists (
    select 1
    from public.conversations c
    where c.id = p_conversation_id
      and auth.uid() in (c.user1, c.user2)
  ) then
    raise exception 'Conversation unavailable';
  end if;

  delete from public.messages
  where conversation_id = p_conversation_id;

  delete from public.conversations
  where id = p_conversation_id
    and auth.uid() in (user1, user2);
end;
$$;

grant execute on function public.delete_direct_conversation(uuid) to authenticated;
