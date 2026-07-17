-- ============================================================================
-- Backfill : des comptes ont été créés (via auth.users) avant que la table
-- public.profiles et son trigger handle_new_user n'existent (migration
-- 0001 appliquée après coup). Ces comptes n'ont donc aucune ligne dans
-- profiles, ce qui fait disparaître le UserMenu (et le bouton déconnexion)
-- dans src/app/(app)/layout.tsx (rendu conditionné par `profile &&`).
-- ============================================================================

insert into public.profiles (id, username, email)
select
  u.id,
  coalesce(u.raw_user_meta_data ->> 'username', 'user_' || substr(u.id::text, 1, 8)),
  u.email
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null;
