-- Fil de discussion par sortie : les participants (et l'organisateur) peuvent
-- se parler de l'événement lui-même directement depuis l'invitation. Le fil
-- est ouvert dès la création de la sortie et reste lisible jusqu'à quelques
-- jours après sa fin — la durée est fixée par l'organisateur à la création
-- (1 à 7 jours, 2 par défaut) et stockée sur `outings.message_retention_days`.
--
-- L'expiration est appliquée par simple filtrage à la lecture (policy RLS) :
-- passé `ends_at + message_retention_days`, les messages ne sont plus
-- sélectionnables ni insérables pour personne. Aucune purge planifiée
-- (pg_cron) n'est mise en place pour l'instant ; les lignes restent en base
-- mais deviennent inaccessibles, ce qui suffit à la promesse produit sans
-- infrastructure supplémentaire.

alter table public.outings
  add column message_retention_days smallint not null default 2
    check (message_retention_days between 1 and 7);

create table public.outing_messages (
  id uuid primary key default gen_random_uuid(),
  outing_id uuid not null references public.outings (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);

alter table public.outing_messages enable row level security;

create policy "outing_messages_select_participants"
  on public.outing_messages for select to authenticated
  using (
    (
      public.is_outing_participant(outing_id, auth.uid())
      or exists (select 1 from public.outings o where o.id = outing_id and o.creator_id = auth.uid())
    )
    and exists (
      select 1 from public.outings o
      where o.id = outing_id
        and now() <= o.ends_at + make_interval(days => o.message_retention_days::int)
    )
  );

create policy "outing_messages_insert_participants"
  on public.outing_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.outings o
      where o.id = outing_id
        and o.cancelled_at is null
        and now() <= o.ends_at + make_interval(days => o.message_retention_days::int)
        and (
          o.creator_id = auth.uid()
          or public.is_outing_participant(outing_id, auth.uid())
        )
    )
  );

create index idx_outing_messages_outing on public.outing_messages (outing_id, created_at);
