-- Signale, sans jamais révéler le contenu de l'invitation, les créneaux où
-- un ami a une invitation de sortie en attente de sa réponse. C'est un
-- signal distinct d'une indisponibilité réelle (get_friends_busy_events) :
-- l'ami n'a encore rien confirmé, mais accepter rendrait ce créneau
-- indisponible. Le titre reste toujours masqué (contrairement au calendrier
-- personnel, il n'y a pas d'opt-in calendar_share_preferences ici) : "en
-- attente" ne dit rien de ce que l'ami ferait concrètement.

create function public.get_friends_pending_outings(
  p_friend_ids uuid[],
  p_range_start date,
  p_range_end date
)
returns setof public.busy_event
language plpgsql
security definer set search_path = public
stable
as $$
begin
  return query
    select distinct
      op.user_id,
      o.starts_at,
      o.ends_at,
      null::text
    from public.outing_participants op
    join public.outings o on o.id = op.outing_id
    where op.user_id = any(p_friend_ids)
      and op.response = 'pending'
      and o.cancelled_at is null
      and o.starts_at < p_range_end::timestamptz
      and o.ends_at > p_range_start::timestamptz
      and exists (
        select 1
        from public.friendships f
        where f.status = 'accepted'
          and (
            (f.requester_id = auth.uid() and f.addressee_id = op.user_id)
            or (f.addressee_id = auth.uid() and f.requester_id = op.user_id)
          )
      );
end;
$$;

comment on function public.get_friends_pending_outings is
  'Retourne, pour les amis (amitié acceptée) demandés, les créneaux où ils ont une invitation de sortie en attente de réponse — jamais le titre ni l''organisateur, juste le signal "peut-être indisponible". Les ids qui ne sont pas des amis acceptés sont silencieusement ignorés.';

grant execute on function public.get_friends_pending_outings(uuid[], date, date) to authenticated;
