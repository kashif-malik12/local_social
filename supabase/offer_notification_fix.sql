alter table public.notifications
  drop constraint if exists notifications_type_check;

alter table public.notifications
  add constraint notifications_type_check
  check (
    type in (
      'follow_request',
      'follow_accepted',
      'follow',
      'like',
      'comment',
      'comment_like',
      'comment_reply',
      'share',
      'mention',
      'offer_message',
      'offer_sent',
      'offer_accepted',
      'offer_rejected'
    )
  ) not valid;

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

  begin
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
  exception
    when others then
      null;
  end;
end;
$$;
