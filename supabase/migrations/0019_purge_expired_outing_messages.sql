-- Complète 0012_outing_messages.sql : les messages expirés étaient jusqu'ici
-- seulement masqués par RLS (les lignes restaient en base indéfiniment,
-- accessibles via un rôle privilégié, un export ou une sauvegarde). Ce
-- fichier ajoute une purge réelle, planifiée quotidiennement via pg_cron,
-- pour que l'expiration du fil corresponde à une suppression effective des
-- données.
--
-- Nécessite l'extension pg_cron activée sur le projet Supabase (Database >
-- Extensions dans le dashboard). Si l'extension n'est pas disponible sur le
-- plan du projet, `create extension` ci-dessous échouera : dans ce cas,
-- l'activer depuis le dashboard puis rejouer cette migration, ou déclencher
-- `select public.purge_expired_outing_messages();` depuis un job externe
-- (ex. Edge Function planifiée) en attendant.

create extension if not exists pg_cron with schema extensions;

create function public.purge_expired_outing_messages()
returns void
language sql
set search_path = public
as $$
  delete from public.outing_messages m
  using public.outings o
  where o.id = m.outing_id
    and now() > o.ends_at + make_interval(days => o.message_retention_days::int);
$$;

comment on function public.purge_expired_outing_messages is
  'Supprime définitivement les messages de sortie dont la fenêtre de rétention (outings.ends_at + message_retention_days) est dépassée. Complète le filtrage RLS de 0012, qui ne fait que masquer les lignes expirées sans les supprimer.';

-- Postgres accorde EXECUTE à PUBLIC par défaut à la création d'une fonction :
-- sans ce revoke explicite, n'importe quel utilisateur authentifié (voire
-- anon) pourrait déclencher cette purge à volonté via l'endpoint RPC
-- PostgREST correspondant. Seul pg_cron (ci-dessous, exécuté en tant que
-- postgres) doit pouvoir l'appeler.
revoke execute on function public.purge_expired_outing_messages() from public;

select cron.schedule(
  'purge-expired-outing-messages',
  '0 3 * * *',
  $$select public.purge_expired_outing_messages();$$
);
