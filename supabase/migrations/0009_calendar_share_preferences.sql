-- Partage optionnel du titre réel d'un événement, activé individuellement
-- par le propriétaire pour un destinataire précis (ami). Comportement par
-- défaut inchangé : sans ligne "enabled" ici, get_friends_busy_events et
-- get_group_busy_events ne renvoient toujours que les plages horaires,
-- jamais le titre.

create table public.calendar_share_preferences (
  owner_id uuid not null references public.profiles (id) on delete cascade,
  viewer_id uuid not null references public.profiles (id) on delete cascade,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (owner_id, viewer_id),
  constraint calendar_share_preferences_not_self check (owner_id <> viewer_id)
);

alter table public.calendar_share_preferences enable row level security;

-- Seul le propriétaire gère ses propres préférences de partage. Le
-- destinataire n'a pas besoin (et n'a pas le droit) de lire cette table
-- directement : les RPC SECURITY DEFINER ci-dessous s'en chargent.
create policy "calendar_share_preferences_owner_all"
  on public.calendar_share_preferences for all
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create trigger set_updated_at before update on public.calendar_share_preferences
  for each row execute procedure public.set_updated_at();

-- Étend le type de retour partagé avec un titre optionnel (null tant que
-- l'appelant n'est pas explicitement autorisé pour cet événement précis).
alter type public.busy_event add attribute title text;

create or replace function public.get_friends_busy_events(
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
    select
      e.user_id,
      e.start_at,
      e.end_at,
      case when sp.owner_id is not null then e.title else null end
    from public.calendar_events e
    left join public.calendar_share_preferences sp
      on sp.owner_id = e.user_id and sp.viewer_id = auth.uid() and sp.enabled
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
  'Retourne les créneaux occupés datés des amis (amitié acceptée) demandés, avec le titre uniquement si le propriétaire a activé le partage pour l''appelant via calendar_share_preferences. Les ids qui ne sont pas des amis acceptés sont silencieusement ignorés.';

create or replace function public.get_group_busy_events(
  p_group_id uuid,
  p_range_start date,
  p_range_end date
)
returns setof public.busy_event
language plpgsql
security definer set search_path = public
stable
as $$
begin
  if not public.is_group_member(p_group_id, auth.uid()) then
    raise exception 'not a member of this group';
  end if;

  return query
    select
      a.user_id,
      a.start_at,
      a.end_at,
      case when sp.owner_id is not null then a.title else null end
    from public.calendar_events a
    join public.group_members gm on gm.user_id = a.user_id
    left join public.calendar_share_preferences sp
      on sp.owner_id = a.user_id and sp.viewer_id = auth.uid() and sp.enabled
    where gm.group_id = p_group_id
      and a.start_at < p_range_end::timestamptz
      and a.end_at > p_range_start::timestamptz;
end;
$$;

comment on function public.get_group_busy_events is
  'Retourne les créneaux occupés datés de tous les membres d''un groupe, avec le titre uniquement si le propriétaire a activé le partage pour l''appelant via calendar_share_preferences (indépendamment de l''appartenance au groupe). Échoue si l''appelant n''est pas membre.';
