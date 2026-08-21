-- Sorties partagées : une invitation porte sur un seul créneau et chaque
-- destinataire répond pour lui-même. Les événements personnels restent privés.

create type public.outing_response as enum ('pending', 'accepted', 'declined');

create table public.outings (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references public.profiles (id) on delete cascade,
  group_id uuid references public.groups (id) on delete set null,
  title text not null check (char_length(trim(title)) between 1 and 120),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  location text,
  note text,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint outing_valid_range check (starts_at < ends_at)
);

create table public.outing_participants (
  outing_id uuid not null references public.outings (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  response public.outing_response not null default 'pending',
  responded_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (outing_id, user_id)
);

create trigger set_updated_at before update on public.outings
  for each row execute procedure public.set_updated_at();

alter table public.outings enable row level security;
alter table public.outing_participants enable row level security;

create function public.is_outing_participant(p_outing_id uuid, p_user_id uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.outing_participants
    where outing_id = p_outing_id and user_id = p_user_id
  );
$$;

create policy "outings_select_participants"
  on public.outings for select to authenticated
  using (creator_id = auth.uid() or public.is_outing_participant(id, auth.uid()));

create policy "outings_insert_creator"
  on public.outings for insert to authenticated
  with check (creator_id = auth.uid());

create policy "outings_update_creator"
  on public.outings for update to authenticated
  using (creator_id = auth.uid()) with check (creator_id = auth.uid());

create policy "outings_delete_creator"
  on public.outings for delete to authenticated
  using (creator_id = auth.uid());

create policy "outing_participants_select_invited"
  on public.outing_participants for select to authenticated
  using (public.is_outing_participant(outing_id, auth.uid()) or exists (
    select 1 from public.outings o where o.id = outing_id and o.creator_id = auth.uid()
  ));

-- L'action serveur vérifie que les destinataires sont des amis acceptés ou
-- membres du groupe ciblé. Cette règle empêche aussi l'insertion directe par
-- un utilisateur qui ne serait pas l'organisateur.
create policy "outing_participants_insert_creator"
  on public.outing_participants for insert to authenticated
  with check (exists (
    select 1
    from public.outings o
    where o.id = outing_id
      and o.creator_id = auth.uid()
      and (
        user_id = auth.uid()
        or exists (
          select 1
          from public.friendships f
          where f.status = 'accepted'
            and (
              (f.requester_id = auth.uid() and f.addressee_id = user_id)
              or (f.addressee_id = auth.uid() and f.requester_id = user_id)
            )
        )
        or (o.group_id is not null and public.is_group_member(o.group_id, user_id))
      )
  ));

create policy "outing_participants_update_own_response"
  on public.outing_participants for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

create index idx_outings_creator_range on public.outings (creator_id, starts_at);
create index idx_outing_participants_user on public.outing_participants (user_id, outing_id);
