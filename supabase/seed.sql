-- Exécuté uniquement en local (supabase start / supabase db reset / supabase
-- test db), jamais poussé vers le projet distant par `supabase db push`.
--
-- Sur la plateforme hébergée Supabase, les privilèges CRUD de base sur les
-- tables `public` sont accordés à anon/authenticated/service_role
-- automatiquement par la plateforme (hors migrations utilisateur), ce qui
-- explique que les migrations de ce repo n'en contiennent aucun. Le CLI
-- local ne reproduit pas ce comportement : sans ces GRANT, toute requête
-- authentifiée échoue avec "permission denied" avant même d'atteindre les
-- policies RLS. On reproduit donc ici l'équivalent, pour que le comportement
-- local (dev, tests pgTAP) corresponde à la prod. La sécurité réelle reste
-- portée par RLS, pas par ces GRANT : anon n'a de policy permissive sur
-- aucune table sensible, donc RLS continue de tout filtrer pour ce rôle.
--
-- Volontairement PAS de grant blanket sur les routines : contrairement aux
-- tables, chaque fonction de ce projet gère son propre `grant execute ...
-- to authenticated` explicite dans sa migration (voir get_group_busy_slots,
-- search_profiles, delete_own_account, etc.). Certaines fonctions comme
-- purge_expired_outing_messages sont volontairement sans grant (appelées
-- uniquement par pg_cron sous un rôle privilégié) : un grant blanket ici
-- masquerait ce genre de frontière et fausserait les tests d'autorisation.

grant usage on schema public to anon, authenticated, service_role;
grant all on all tables in schema public to anon, authenticated, service_role;
grant all on all sequences in schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
