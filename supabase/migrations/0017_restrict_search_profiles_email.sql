-- search_profiles (0001_init.sql) est SECURITY DEFINER et contourne RLS pour
-- permettre de retrouver un profil par pseudo/email avant d'être amis. Elle
-- renvoyait `public.profiles` en entier (select *), donc l'email réel de
-- n'importe quel utilisateur correspondant à une simple sous-chaîne de pseudo
-- (ex. une seule lettre) était exposé à n'importe quel utilisateur connecté,
-- sans limite de requêtes — une fuite de données personnelles, pas seulement
-- une recherche trop permissive.
--
-- Fix : la fonction ne renvoie plus jamais la colonne email, seulement
-- id/username/avatar_url. La recherche par email reste possible (correspondance
-- exacte uniquement, jamais par sous-chaîne) pour retrouver un ami dont on
-- connaît déjà l'adresse, sans jamais révéler l'email d'un inconnu.

drop function if exists public.search_profiles(text);

create function public.search_profiles(p_query text)
returns table (id uuid, username text, avatar_url text)
language sql
security definer set search_path = public
stable
as $$
  select p.id, p.username, p.avatar_url
  from public.profiles p
  where p.id <> auth.uid()
    and (p.username ilike '%' || p_query || '%' or p.email = p_query)
  limit 10;
$$;

comment on function public.search_profiles is
  'Recherche de profils par pseudo (sous-chaîne) ou email (correspondance exacte) pour ajouter un ami. Ne renvoie jamais la colonne email : uniquement id/username/avatar_url, pour empêcher l''énumération d''adresses email par recherche de pseudo partiel.';

grant execute on function public.search_profiles(text) to authenticated;
