-- Une sortie n'est affichée comme confirmée que si tout le monde a répondu
-- (accepté ou décliné), ou que l'organisateur la confirme explicitement —
-- utile pour un gros groupe où attendre 100% des réponses n'est pas
-- réaliste. `confirmed_at` reste modifiable par le créateur via la policy
-- `outings_update_creator` déjà en place (0005_outings.sql).

alter table public.outings
  add column confirmed_at timestamptz;
