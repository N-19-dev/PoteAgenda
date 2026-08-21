-- Suppression de compte à l'initiative de l'utilisateur, exigée par l'App
-- Store Review Guideline 5.1.1(v) : toute app permettant de créer un compte
-- doit permettre de le supprimer (pas seulement de se déconnecter)
-- directement depuis l'app.
--
-- Toutes les tables métier référencent profiles(id) -> auth.users(id) en
-- cascade (on delete cascade), donc supprimer la ligne auth.users suffit à
-- purger l'intégralité des données de l'utilisateur : profil,
-- calendar_events, calendar_sources, friendships, group_members,
-- calendar_share_preferences (comme owner ou viewer), outing_participants,
-- outing_messages envoyés.
--
-- Limitation connue : groups.owner_id est on delete cascade, donc un groupe
-- dont l'utilisateur est owner est supprimé pour tous ses membres (pas de
-- transfert de propriété implémenté). outings.group_id est on delete set
-- null (le groupe reste si le owner d'origine change). Les
-- mentioned_user_ids d'outing_messages (uuid[] sans FK, cf. 0012) peuvent
-- garder un id résiduel : sans conséquence, pas une frontière de sécurité.

create function public.delete_own_account()
returns void
language plpgsql
security definer set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  delete from auth.users where id = auth.uid();
end;
$$;

comment on function public.delete_own_account is
  'Supprime définitivement le compte de l''appelant (auth.users + toutes les données liées via cascade). Irréversible.';

grant execute on function public.delete_own_account() to authenticated;
