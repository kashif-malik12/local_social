create extension if not exists pgcrypto;

create table if not exists public.offer_conversations (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  buyer_id uuid not null references public.profiles(id) on delete cascade,
  seller_id uuid not null references public.profiles(id) on delete cascade,
  current_offer_amount numeric,
  current_offer_status text not null default 'none'
    check (current_offer_status in ('none', 'pending', 'accepted', 'rejected')),
  current_offer_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint offer_conversations_buyer_seller_diff check (buyer_id <> seller_id),
  constraint offer_conversations_unique unique (post_id, buyer_id, seller_id)
);

create index if not exists offer_conversations_post_idx
  on public.offer_conversations(post_id);

create index if not exists offer_conversations_buyer_idx
  on public.offer_conversations(buyer_id);

create index if not exists offer_conversations_seller_idx
  on public.offer_conversations(seller_id);

create table if not exists public.offer_messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.offer_conversations(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  message_type text not null default 'text'
    check (message_type in ('text', 'offer', 'counter', 'accepted', 'rejected')),
  content text not null default '',
  offer_amount numeric,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint offer_messages_content_or_amount check (
    (message_type = 'text' and length(trim(content)) > 0)
    or (message_type in ('offer', 'counter') and offer_amount is not null and offer_amount > 0)
    or (message_type in ('accepted', 'rejected'))
  )
);

create index if not exists offer_messages_conversation_idx
  on public.offer_messages(conversation_id, created_at desc);

create index if not exists offer_messages_unread_idx
  on public.offer_messages(conversation_id, sender_id, read_at);

create or replace function public.set_offer_conversation_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_offer_conversations_updated_at on public.offer_conversations;
create trigger trg_offer_conversations_updated_at
before update on public.offer_conversations
for each row
execute function public.set_offer_conversation_updated_at();

alter table public.offer_conversations enable row level security;
alter table public.offer_messages enable row level security;

drop policy if exists offer_conversations_select_participants on public.offer_conversations;
create policy offer_conversations_select_participants
on public.offer_conversations
for select
to authenticated
using (auth.uid() = buyer_id or auth.uid() = seller_id);

drop policy if exists offer_conversations_insert_participants on public.offer_conversations;
create policy offer_conversations_insert_participants
on public.offer_conversations
for insert
to authenticated
with check (auth.uid() = buyer_id or auth.uid() = seller_id);

drop policy if exists offer_conversations_delete_participants on public.offer_conversations;
create policy offer_conversations_delete_participants
on public.offer_conversations
for delete
to authenticated
using (auth.uid() = buyer_id or auth.uid() = seller_id);

drop policy if exists offer_conversations_update_participants on public.offer_conversations;
create policy offer_conversations_update_participants
on public.offer_conversations
for update
to authenticated
using (auth.uid() = buyer_id or auth.uid() = seller_id)
with check (auth.uid() = buyer_id or auth.uid() = seller_id);

drop policy if exists offer_messages_select_participants on public.offer_messages;
create policy offer_messages_select_participants
on public.offer_messages
for select
to authenticated
using (
  exists (
    select 1
    from public.offer_conversations c
    where c.id = offer_messages.conversation_id
      and (auth.uid() = c.buyer_id or auth.uid() = c.seller_id)
  )
);

drop policy if exists offer_messages_insert_sender on public.offer_messages;
create policy offer_messages_insert_sender
on public.offer_messages
for insert
to authenticated
with check (
  auth.uid() = sender_id
  and exists (
    select 1
    from public.offer_conversations c
    where c.id = offer_messages.conversation_id
      and (auth.uid() = c.buyer_id or auth.uid() = c.seller_id)
  )
);

drop policy if exists offer_messages_update_participants on public.offer_messages;
create policy offer_messages_update_participants
on public.offer_messages
for update
to authenticated
using (
  exists (
    select 1
    from public.offer_conversations c
    where c.id = offer_messages.conversation_id
      and (auth.uid() = c.buyer_id or auth.uid() = c.seller_id)
  )
)
with check (
  exists (
    select 1
    from public.offer_conversations c
    where c.id = offer_messages.conversation_id
      and (auth.uid() = c.buyer_id or auth.uid() = c.seller_id)
  )
);

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

create or replace function public.create_offer_notification(
  p_recipient_id uuid,
  p_actor_id uuid,
  p_post_id uuid,
  p_type text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_recipient_id is null or p_actor_id is null or p_post_id is null then
    return;
  end if;

  if p_recipient_id = p_actor_id then
    return;
  end if;

  insert into public.notifications (
    recipient_id,
    actor_id,
    post_id,
    type
  )
  values (
    p_recipient_id,
    p_actor_id,
    p_post_id,
    p_type
  );
end;
$$;

create or replace function public.get_offer_chat_list()
returns table (
  conversation_id uuid,
  post_id uuid,
  post_type text,
  post_title text,
  market_price numeric,
  other_user_id uuid,
  other_full_name text,
  last_message text,
  unread_count bigint,
  current_offer_amount numeric,
  current_offer_status text,
  updated_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  with base as (
    select
      c.id as conversation_id,
      c.post_id,
      p.post_type,
      coalesce(nullif(trim(p.market_title), ''), nullif(trim(p.content), ''), 'Listing') as post_title,
      p.market_price,
      c.current_offer_amount,
      c.current_offer_status,
      c.updated_at,
      case
        when auth.uid() = c.buyer_id then c.seller_id
        else c.buyer_id
      end as other_user_id,
      case
        when auth.uid() = c.buyer_id then seller.full_name
        else buyer.full_name
      end as other_full_name
    from public.offer_conversations c
    join public.posts p on p.id = c.post_id
    join public.profiles buyer on buyer.id = c.buyer_id
    join public.profiles seller on seller.id = c.seller_id
    where auth.uid() in (c.buyer_id, c.seller_id)
  ),
  last_msg as (
    select distinct on (m.conversation_id)
      m.conversation_id,
      case
        when m.message_type in ('offer', 'counter') then concat(initcap(m.message_type), ': EUR ', m.offer_amount)
        when m.message_type = 'accepted' then 'Offer accepted'
        when m.message_type = 'rejected' then 'Offer rejected'
        else m.content
      end as content,
      m.created_at
    from public.offer_messages m
    order by m.conversation_id, m.created_at desc, m.id desc
  ),
  unread as (
    select
      m.conversation_id,
      count(*)::bigint as unread_count
    from public.offer_messages m
    join public.offer_conversations c on c.id = m.conversation_id
    where m.sender_id <> auth.uid()
      and m.read_at is null
      and auth.uid() in (c.buyer_id, c.seller_id)
    group by m.conversation_id
  )
  select
    b.conversation_id,
    b.post_id,
    b.post_type,
    b.post_title,
    b.market_price,
    b.other_user_id,
    b.other_full_name,
    lm.content as last_message,
    coalesce(u.unread_count, 0) as unread_count,
    b.current_offer_amount,
    b.current_offer_status,
    coalesce(lm.created_at, b.updated_at) as updated_at
  from base b
  left join last_msg lm on lm.conversation_id = b.conversation_id
  left join unread u on u.conversation_id = b.conversation_id
  order by updated_at desc nulls last;
$$;

create or replace function public.get_offer_messages(
  p_conversation_id uuid,
  p_limit integer default 50,
  p_before timestamptz default null
)
returns table (
  id uuid,
  conversation_id uuid,
  sender_id uuid,
  message_type text,
  content text,
  offer_amount numeric,
  created_at timestamptz,
  read_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    m.id,
    m.conversation_id,
    m.sender_id,
    m.message_type,
    m.content,
    m.offer_amount,
    m.created_at,
    m.read_at
  from public.offer_messages m
  join public.offer_conversations c on c.id = m.conversation_id
  where m.conversation_id = p_conversation_id
    and auth.uid() in (c.buyer_id, c.seller_id)
    and (p_before is null or m.created_at < p_before)
  order by m.created_at desc, m.id desc
  limit greatest(coalesce(p_limit, 50), 1);
$$;

create or replace function public.send_offer_message(
  p_conversation_id uuid,
  p_content text
)
returns table (
  id uuid,
  conversation_id uuid,
  sender_id uuid,
  message_type text,
  content text,
  offer_amount numeric,
  created_at timestamptz,
  read_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conversation public.offer_conversations%rowtype;
  v_recipient_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if trim(coalesce(p_content, '')) = '' then
    raise exception 'Message cannot be empty';
  end if;

  if not exists (
    select 1
    from public.offer_conversations c
    join public.posts p on p.id = c.post_id
    where c.id = p_conversation_id
      and auth.uid() in (c.buyer_id, c.seller_id)
      and p.post_type in ('market', 'service_offer', 'service_request')
    ) then
      raise exception 'Offer chat unavailable';
    end if;

  select *
  into v_conversation
  from public.offer_conversations c
  where c.id = p_conversation_id
    and auth.uid() in (c.buyer_id, c.seller_id);

  v_recipient_id := case
    when auth.uid() = v_conversation.buyer_id then v_conversation.seller_id
    else v_conversation.buyer_id
  end;

  update public.offer_conversations
  set updated_at = now()
  where public.offer_conversations.id = p_conversation_id;

  perform public.create_offer_notification(
    v_recipient_id,
    auth.uid(),
    v_conversation.post_id,
    'offer_message'
  );

  return query
  insert into public.offer_messages (conversation_id, sender_id, message_type, content)
  values (p_conversation_id, auth.uid(), 'text', trim(p_content))
  returning
    offer_messages.id,
    offer_messages.conversation_id,
    offer_messages.sender_id,
    offer_messages.message_type,
    offer_messages.content,
    offer_messages.offer_amount,
    offer_messages.created_at,
    offer_messages.read_at;
end;
$$;

create or replace function public.submit_offer_amount(
  p_conversation_id uuid,
  p_amount numeric
)
returns table (
  id uuid,
  conversation_id uuid,
  sender_id uuid,
  message_type text,
  content text,
  offer_amount numeric,
  created_at timestamptz,
  read_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conversation public.offer_conversations%rowtype;
  v_kind text;
  v_recipient_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if p_amount is null or p_amount <= 0 then
    raise exception 'Offer amount must be greater than zero';
  end if;

  select *
  into v_conversation
  from public.offer_conversations c
  where c.id = p_conversation_id
    and auth.uid() in (c.buyer_id, c.seller_id);

  if not found then
    raise exception 'Offer chat unavailable';
  end if;

  v_kind := case
    when v_conversation.current_offer_amount is null then 'offer'
    else 'counter'
  end;

  v_recipient_id := case
    when auth.uid() = v_conversation.buyer_id then v_conversation.seller_id
    else v_conversation.buyer_id
  end;

  update public.offer_conversations
  set current_offer_amount = p_amount,
      current_offer_status = 'pending',
      current_offer_by = auth.uid(),
      updated_at = now()
  where public.offer_conversations.id = p_conversation_id;

  return query
  insert into public.offer_messages (
    conversation_id,
    sender_id,
    message_type,
    offer_amount,
    content
  )
  values (
    p_conversation_id,
    auth.uid(),
    v_kind,
    p_amount,
    ''
  )
  returning
    offer_messages.id,
    offer_messages.conversation_id,
    offer_messages.sender_id,
    offer_messages.message_type,
    offer_messages.content,
    offer_messages.offer_amount,
    offer_messages.created_at,
    offer_messages.read_at;

  perform public.create_offer_notification(
    v_recipient_id,
    auth.uid(),
    v_conversation.post_id,
    'offer_sent'
  );
end;
$$;

create or replace function public.respond_to_offer(
  p_conversation_id uuid,
  p_decision text
)
returns table (
  id uuid,
  conversation_id uuid,
  sender_id uuid,
  message_type text,
  content text,
  offer_amount numeric,
  created_at timestamptz,
  read_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_conversation public.offer_conversations%rowtype;
  v_decision text := lower(trim(coalesce(p_decision, '')));
  v_recipient_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if v_decision not in ('accepted', 'rejected') then
    raise exception 'Decision must be accepted or rejected';
  end if;

  select *
  into v_conversation
  from public.offer_conversations c
  where c.id = p_conversation_id
    and auth.uid() in (c.buyer_id, c.seller_id);

  if not found then
    raise exception 'Offer chat unavailable';
  end if;

  if v_conversation.current_offer_amount is null
     or v_conversation.current_offer_status <> 'pending' then
    raise exception 'There is no pending offer to respond to';
  end if;

  if v_conversation.current_offer_by = auth.uid() then
    raise exception 'You cannot respond to your own offer';
  end if;

  v_recipient_id := case
    when auth.uid() = v_conversation.buyer_id then v_conversation.seller_id
    else v_conversation.buyer_id
  end;

  update public.offer_conversations
  set current_offer_status = v_decision,
      updated_at = now()
  where public.offer_conversations.id = p_conversation_id;

  return query
  insert into public.offer_messages (
    conversation_id,
    sender_id,
    message_type,
    offer_amount,
    content
  )
  values (
    p_conversation_id,
    auth.uid(),
    v_decision,
    v_conversation.current_offer_amount,
    ''
  )
  returning
    offer_messages.id,
    offer_messages.conversation_id,
    offer_messages.sender_id,
    offer_messages.message_type,
    offer_messages.content,
    offer_messages.offer_amount,
    offer_messages.created_at,
    offer_messages.read_at;

  perform public.create_offer_notification(
    v_recipient_id,
    auth.uid(),
    v_conversation.post_id,
    case
      when v_decision = 'accepted' then 'offer_accepted'
      else 'offer_rejected'
    end
  );
end;
$$;

create or replace function public.mark_offer_conversation_read(
  p_conversation_id uuid
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  update public.offer_messages m
  set read_at = now()
  where m.conversation_id = p_conversation_id
    and m.sender_id <> auth.uid()
    and m.read_at is null
    and exists (
      select 1
      from public.offer_conversations c
      where c.id = p_conversation_id
        and auth.uid() in (c.buyer_id, c.seller_id)
    );

  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.delete_offer_conversation(
  p_conversation_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.offer_conversations c
  where c.id = p_conversation_id
    and auth.uid() in (c.buyer_id, c.seller_id);

  if not found then
    raise exception 'Offer chat unavailable';
  end if;
end;
$$;

grant execute on function public.get_or_create_offer_conversation(uuid, uuid) to authenticated;
grant execute on function public.create_offer_notification(uuid, uuid, uuid, text) to authenticated;
grant execute on function public.get_offer_chat_list() to authenticated;
grant execute on function public.get_offer_messages(uuid, integer, timestamptz) to authenticated;
grant execute on function public.send_offer_message(uuid, text) to authenticated;
grant execute on function public.submit_offer_amount(uuid, numeric) to authenticated;
grant execute on function public.respond_to_offer(uuid, text) to authenticated;
grant execute on function public.mark_offer_conversation_read(uuid) to authenticated;
grant execute on function public.delete_offer_conversation(uuid) to authenticated;
