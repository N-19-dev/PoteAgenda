-- La policy initiale `profiles_select_authenticated` (0001_init.sql) autorise
-- `using (true)` : n'importe quel utilisateur connecté peut faire
-- `GET /rest/v1/profiles?select=*` et récupérer l'email et le pseudo de
-- TOUS les utilisateurs de l'app, amis ou pas. C'est une fuite de données
-- personnelles, pas seulement un oubli de scope.
--
-- La recherche de profils par pseudo/email pour ajouter un ami continue de
-- fonctionner : elle passe par `search_profiles`, une fonction
-- SECURITY DEFINER qui contourne intentionnellement RLS (comme
-- get_group_busy_events et get_friends_busy_events) et n'est donc pas
-- affectée par ce resserrement.
--
-- Les seuls appels directs à /rest/v1/profiles depuis le client (résolution
-- d'ids pour afficher amis/membres de groupe/participants de sortie) restent
-- couverts par cette policy plus stricte : un profil n'est lisible que par
-- lui-même, par une personne liée par une demande d'ami (peu importe le
-- statut, pour voir les demandes en attente), par un membre du même groupe,
-- ou par un participant/organisateur de la même sortie.

drop policy "profiles_select_authenticated" on public.profiles;

create policy "profiles_select_related"
  on public.profiles for select
  to authenticated
  using (
    id = auth.uid()
    or exists (
      select 1 from public.friendships f
      where (f.requester_id = auth.uid() and f.addressee_id = profiles.id)
         or (f.addressee_id = auth.uid() and f.requester_id = profiles.id)
    )
    or exists (
      select 1 from public.group_members gm
      where gm.user_id = profiles.id
        and public.is_group_member(gm.group_id, auth.uid())
    )
    or exists (
      select 1 from public.outing_participants op
      where op.user_id = profiles.id
        and (
          public.is_outing_participant(op.outing_id, auth.uid())
          or exists (
            select 1 from public.outings o
            where o.id = op.outing_id and o.creator_id = auth.uid()
          )
        )
    )
    or exists (
      select 1 from public.outings o
      where o.creator_id = profiles.id
        and public.is_outing_participant(o.id, auth.uid())
    )
  );
