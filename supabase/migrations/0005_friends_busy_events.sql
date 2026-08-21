-- ============================================================================
-- PoteAgenda — disponibilités d'amis directement sur l'agenda perso
-- ============================================================================
-- Jusqu'ici, voir les créneaux "occupé" d'un autre utilisateur nécessitait de
-- partager un groupe (get_group_busy_events). Le calendrier perso permet
-- désormais de filtrer par amis directement, sans passer par un groupe :
-- cette fonction applique la même garantie de confidentialité (jamais de
-- titre/couleur, uniquement des plages horaires) mais vérifie une amitié
-- acceptée (bidirectionnelle) au lieu d'une appartenance à un groupe.
-- ============================================================================

create function public.get_friends_busy_events(
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
    select e.user_id, e.start_at, e.end_at
    from public.calendar_events e
    where e.user_id = any(p_friend_ids)
      and e.start_at < p_range_end::timestamptz
      and e.end_at > p_range_start::timestamptz
      and exists (
        select 1
        from public.friendships f
        where f.status = 'accepted'
          and (
            (f.requester_id = auth.uid() and f.addressee_id = e.user_id)
            or (f.addressee_id = auth.uid() and f.requester_id = e.user_id)
          )
      );
end;
$$;

comment on function public.get_friends_busy_events is
  'Retourne les créneaux occupés datés (sans titre ni couleur) des amis (amitié acceptée) demandés. Les ids qui ne sont pas des amis acceptés sont silencieusement ignorés.';

grant execute on function public.get_friends_busy_events(uuid[], date, date) to authenticated;
