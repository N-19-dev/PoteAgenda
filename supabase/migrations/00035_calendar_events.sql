-- ============================================================================
-- PoteAgenda — passage au modèle daté (calendrier réel) + calendriers importés
-- ============================================================================
-- Remplace le modèle hebdomadaire récurrent (`availabilities`, day_of_week)
-- par un modèle daté (`calendar_events`, start_at/end_at en timestamptz), pour
-- permettre l'import d'un vrai calendrier externe (.ics, fichier ou URL).
-- Même garantie de confidentialité que l'ancien modèle : RLS stricte
-- (personne d'autre que le propriétaire ne peut lire les lignes brutes) +
-- RPC SECURITY DEFINER qui ne renvoie jamais titre/couleur, seulement les
-- plages "occupé" datées des membres d'un groupe partagé.
--
-- Environnement de développement sans donnée à préserver : migration
-- destructive (drop + recréation), pas de conversion de données.
-- ============================================================================

drop function if exists public.get_group_busy_slots(uuid);
drop type if exists public.busy_slot;
drop table if exists public.availabilities;

-- ----------------------------------------------------------------------------
-- 1. CALENDAR_SOURCES — calendriers externes connectés (fichier ou URL .ics)
-- ----------------------------------------------------------------------------
create table public.calendar_sources (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references public.profiles (id) on delete cascade,
  label           text not null,
  kind            text not null check (kind in ('file', 'url')),
  ics_url         text,
  last_synced_at  timestamptz,
  created_at      timestamptz not null default now(),

  constraint ics_url_requires_url_kind check (kind <> 'url' or ics_url is not null)
);

comment on table public.calendar_sources is
  'Calendriers externes connectés par l''utilisateur (import .ics). L''URL est un secret : même garantie de confidentialité que les titres d''événements (RLS stricte, jamais exposée à un autre utilisateur).';

alter table public.calendar_sources enable row level security;

create policy "calendar_sources_all_own"
  on public.calendar_sources for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- 2. CALENDAR_EVENTS — agenda perso daté (remplace availabilities)
-- ----------------------------------------------------------------------------
create table public.calendar_events (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  title       text not null default 'Occupé',
  start_at    timestamptz not null,
  end_at      timestamptz not null,
  color       text not null default '#6366f1',
  source      text not null default 'manual' check (source in ('manual', 'ics')),
  source_id   uuid references public.calendar_sources (id) on delete cascade,
  external_uid text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint valid_range check (start_at < end_at),
  constraint source_consistency check (
    (source = 'manual' and source_id is null) or
    (source = 'ics' and source_id is not null)
  )
);

comment on column public.calendar_events.title is
  'Visible uniquement par le propriétaire. Jamais exposé aux autres utilisateurs (cf. RLS + RPC get_group_busy_events).';

alter table public.calendar_events enable row level security;

-- Verrouillage strict : personne d'autre que le propriétaire ne peut lire
-- les lignes brutes (donc jamais le titre). Le partage "occupé" passe
-- uniquement par la fonction get_group_busy_events ci-dessous.
create policy "calendar_events_all_own"
  on public.calendar_events for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create trigger set_updated_at before update on public.calendar_events
  for each row execute procedure public.set_updated_at();

-- ----------------------------------------------------------------------------
-- 3. RPC — resync transactionnel d'une source importée
-- ----------------------------------------------------------------------------
-- Remplace en une seule transaction toutes les occurrences d'une source par
-- celles fraîchement parsées côté serveur (route handler), et met à jour
-- last_synced_at. L'appartenance de la source est revérifiée ici (défense en
-- profondeur, en plus du filtre applicatif côté route handler).
create type public.calendar_event_input as (
  title        text,
  start_at     timestamptz,
  end_at       timestamptz,
  color        text,
  external_uid text
);

create function public.resync_calendar_source(
  p_source_id uuid,
  p_events public.calendar_event_input[]
)
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if not exists (
    select 1 from public.calendar_sources
    where id = p_source_id and user_id = auth.uid()
  ) then
    raise exception 'not the owner of this calendar source';
  end if;

  delete from public.calendar_events
  where source_id = p_source_id and user_id = auth.uid();

  insert into public.calendar_events (user_id, title, start_at, end_at, color, source, source_id, external_uid)
  select auth.uid(), e.title, e.start_at, e.end_at, e.color, 'ics', p_source_id, e.external_uid
  from unnest(p_events) as e;

  update public.calendar_sources
  set last_synced_at = now()
  where id = p_source_id and user_id = auth.uid();
end;
$$;

comment on function public.resync_calendar_source is
  'Remplace transactionnellement les occurrences importées d''une source (delete+insert) et met à jour last_synced_at. Échoue si l''appelant n''est pas propriétaire de la source.';

grant execute on function public.resync_calendar_source(uuid, public.calendar_event_input[]) to authenticated;

-- ----------------------------------------------------------------------------
-- 4. RPC — créneaux "occupé" datés agrégés d'un groupe (sans titre)
-- ----------------------------------------------------------------------------
create type public.busy_event as (
  user_id  uuid,
  start_at timestamptz,
  end_at   timestamptz
);

create function public.get_group_busy_events(
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
    select a.user_id, a.start_at, a.end_at
    from public.calendar_events a
    join public.group_members gm on gm.user_id = a.user_id
    where gm.group_id = p_group_id
      and a.start_at < p_range_end::timestamptz
      and a.end_at > p_range_start::timestamptz;
end;
$$;

comment on function public.get_group_busy_events is
  'Retourne les créneaux occupés datés (sans titre ni couleur) de tous les membres d''un groupe sur une plage de dates. Échoue si l''appelant n''est pas membre.';

grant execute on function public.get_group_busy_events(uuid, date, date) to authenticated;

-- ----------------------------------------------------------------------------
-- 5. Index
-- ----------------------------------------------------------------------------
create index idx_calendar_sources_user on public.calendar_sources (user_id);
create index idx_calendar_events_user_range on public.calendar_events (user_id, start_at, end_at);
create index idx_calendar_events_source on public.calendar_events (source_id);
