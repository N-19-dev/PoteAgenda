-- ============================================================================
-- PoteAgenda — schéma initial
-- ============================================================================
-- Convention : toutes les tables métier référencent auth.users via un
-- profil public (profiles). La confidentialité des créneaux est assurée par
-- des RLS strictes sur `availabilities` (personne d'autre que le propriétaire
-- ne peut lire les lignes brutes) + une fonction RPC SECURITY DEFINER qui ne
-- renvoie jamais le titre/la couleur d'un événement, uniquement les plages
-- "occupé" des membres d'un groupe partagé.
-- ============================================================================

create extension if not exists "pgcrypto";

-- ----------------------------------------------------------------------------
-- 1. PROFILES
-- ----------------------------------------------------------------------------
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  username    text not null unique,
  email       text not null,
  avatar_url  text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint username_format check (username ~ '^[a-z0-9_.]{3,20}$')
);

comment on table public.profiles is 'Profil public minimal associé à chaque utilisateur auth.';

alter table public.profiles enable row level security;

-- Tout utilisateur connecté peut voir les profils publics (nécessaire pour
-- rechercher un ami par pseudo/email et afficher les membres d'un groupe).
create policy "profiles_select_authenticated"
  on public.profiles for select
  to authenticated
  using (true);

create policy "profiles_update_own"
  on public.profiles for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

create policy "profiles_insert_own"
  on public.profiles for insert
  to authenticated
  with check (id = auth.uid());

-- Création automatique du profil à l'inscription Supabase Auth.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username, email)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data ->> 'username',
      'user_' || substr(new.id::text, 1, 8)
    ),
    new.email
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ----------------------------------------------------------------------------
-- 2. FRIENDSHIPS (demande / acceptation)
-- ----------------------------------------------------------------------------
create type public.friendship_status as enum ('pending', 'accepted', 'declined', 'blocked');

create table public.friendships (
  id            uuid primary key default gen_random_uuid(),
  requester_id  uuid not null references public.profiles (id) on delete cascade,
  addressee_id  uuid not null references public.profiles (id) on delete cascade,
  status        public.friendship_status not null default 'pending',
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint no_self_friendship check (requester_id <> addressee_id)
);

comment on table public.friendships is 'Relations d''amitié entre profils, avec flux demande/acceptation.';

-- Empêche les doublons (A->B) et (B->A) grâce à une paire triée normalisée.
-- Une contrainte UNIQUE ne peut pas porter sur des expressions ; il faut un index unique.
create unique index unique_pair on public.friendships (least(requester_id, addressee_id), greatest(requester_id, addressee_id));

alter table public.friendships enable row level security;

create policy "friendships_select_involved"
  on public.friendships for select
  to authenticated
  using (auth.uid() in (requester_id, addressee_id));

create policy "friendships_insert_as_requester"
  on public.friendships for insert
  to authenticated
  with check (auth.uid() = requester_id);

-- Seul le destinataire peut accepter/refuser ; les deux parties peuvent
-- rompre une amitié acceptée (mise à jour vers 'declined' ou suppression).
create policy "friendships_update_involved"
  on public.friendships for update
  to authenticated
  using (auth.uid() in (requester_id, addressee_id))
  with check (auth.uid() in (requester_id, addressee_id));

create policy "friendships_delete_involved"
  on public.friendships for delete
  to authenticated
  using (auth.uid() in (requester_id, addressee_id));

-- ----------------------------------------------------------------------------
-- 3. GROUPS & GROUP_MEMBERS
-- ----------------------------------------------------------------------------
create table public.groups (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  description text,
  owner_id    uuid not null references public.profiles (id) on delete cascade,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.groups enable row level security;

create type public.group_role as enum ('owner', 'member');

create table public.group_members (
  group_id  uuid not null references public.groups (id) on delete cascade,
  user_id   uuid not null references public.profiles (id) on delete cascade,
  role      public.group_role not null default 'member',
  joined_at timestamptz not null default now(),

  primary key (group_id, user_id)
);

alter table public.group_members enable row level security;

-- Fonction utilitaire (SECURITY DEFINER) pour éviter la récursion RLS
-- classique entre `groups` et `group_members`.
create function public.is_group_member(p_group_id uuid, p_user_id uuid)
returns boolean
language sql
security definer set search_path = public
stable
as $$
  select exists (
    select 1 from public.group_members
    where group_id = p_group_id and user_id = p_user_id
  );
$$;

create policy "groups_select_members"
  on public.groups for select
  to authenticated
  using (public.is_group_member(id, auth.uid()));

create policy "groups_insert_as_owner"
  on public.groups for insert
  to authenticated
  with check (owner_id = auth.uid());

create policy "groups_update_owner"
  on public.groups for update
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create policy "groups_delete_owner"
  on public.groups for delete
  to authenticated
  using (owner_id = auth.uid());

create policy "group_members_select_members"
  on public.group_members for select
  to authenticated
  using (public.is_group_member(group_id, auth.uid()));

-- Seul le owner du groupe ajoute/retire des membres (MVP : pas d'auto-invite).
create policy "group_members_insert_owner"
  on public.group_members for insert
  to authenticated
  with check (
    exists (select 1 from public.groups g where g.id = group_id and g.owner_id = auth.uid())
    or user_id = auth.uid() -- permet au owner d'être inséré comme premier membre
  );

create policy "group_members_delete_owner_or_self"
  on public.group_members for delete
  to authenticated
  using (
    user_id = auth.uid()
    or exists (select 1 from public.groups g where g.id = group_id and g.owner_id = auth.uid())
  );

-- ----------------------------------------------------------------------------
-- 4. AVAILABILITIES — agenda perso hebdomadaire (MVP : créneaux récurrents)
-- ----------------------------------------------------------------------------
create table public.availabilities (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references public.profiles (id) on delete cascade,
  title       text not null default 'Occupé',
  day_of_week smallint not null check (day_of_week between 0 and 6), -- 0 = lundi
  start_time  time not null,
  end_time    time not null,
  color       text not null default '#6366f1',
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint valid_range check (start_time < end_time)
);

comment on column public.availabilities.title is
  'Visible uniquement par le propriétaire. Jamais exposé aux autres utilisateurs (cf. RLS + RPC get_group_busy_slots).';

alter table public.availabilities enable row level security;

-- Verrouillage strict : personne d'autre que le propriétaire ne peut lire
-- les lignes brutes (donc jamais le titre). Le partage "Occupé" passe
-- uniquement par la fonction get_group_busy_slots ci-dessous.
create policy "availabilities_all_own"
  on public.availabilities for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- ----------------------------------------------------------------------------
-- 5. RPC — créneaux "occupé" agrégés d'un groupe (sans titre)
-- ----------------------------------------------------------------------------
create type public.busy_slot as (
  user_id     uuid,
  day_of_week smallint,
  start_time  time,
  end_time    time
);

create function public.get_group_busy_slots(p_group_id uuid)
returns setof public.busy_slot
language plpgsql
security definer set search_path = public
stable
as $$
begin
  if not public.is_group_member(p_group_id, auth.uid()) then
    raise exception 'not a member of this group';
  end if;

  return query
    select a.user_id, a.day_of_week, a.start_time, a.end_time
    from public.availabilities a
    join public.group_members gm on gm.user_id = a.user_id
    where gm.group_id = p_group_id;
end;
$$;

comment on function public.get_group_busy_slots is
  'Retourne les créneaux occupés (sans titre ni couleur) de tous les membres d''un groupe. Échoue si l''appelant n''est pas membre.';

grant execute on function public.get_group_busy_slots(uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 6. RPC — recherche de profils (ajout d'amis par pseudo/email)
-- ----------------------------------------------------------------------------
create function public.search_profiles(p_query text)
returns setof public.profiles
language sql
security definer set search_path = public
stable
as $$
  select *
  from public.profiles
  where id <> auth.uid()
    and (username ilike '%' || p_query || '%' or email ilike '%' || p_query || '%')
  limit 10;
$$;

grant execute on function public.search_profiles(text) to authenticated;

-- ----------------------------------------------------------------------------
-- 7. Triggers updated_at génériques
-- ----------------------------------------------------------------------------
create function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger set_updated_at before update on public.profiles
  for each row execute procedure public.set_updated_at();
create trigger set_updated_at before update on public.friendships
  for each row execute procedure public.set_updated_at();
create trigger set_updated_at before update on public.groups
  for each row execute procedure public.set_updated_at();
create trigger set_updated_at before update on public.availabilities
  for each row execute procedure public.set_updated_at();

-- ----------------------------------------------------------------------------
-- 8. Index
-- ----------------------------------------------------------------------------
create index idx_friendships_requester on public.friendships (requester_id);
create index idx_friendships_addressee on public.friendships (addressee_id);
create index idx_group_members_user on public.group_members (user_id);
create index idx_availabilities_user on public.availabilities (user_id);
create index idx_availabilities_user_day on public.availabilities (user_id, day_of_week);
