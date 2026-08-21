begin;
select plan(5);

select tests.create_test_user('11111111-1111-1111-1111-111111111501', 'organizer');
select tests.create_test_user('11111111-1111-1111-1111-111111111502', 'participant');

-- Sortie déjà terminée, rétention de 1 jour déjà dépassée : le fil est
-- expiré depuis longtemps.
insert into public.outings (id, creator_id, title, starts_at, ends_at, message_retention_days)
values (
  '22222222-2222-2222-2222-222222222501', '11111111-1111-1111-1111-111111111501',
  'Sortie expirée', now() - interval '10 days', now() - interval '9 days', 1
);
insert into public.outing_participants (outing_id, user_id, response)
values ('22222222-2222-2222-2222-222222222501', '11111111-1111-1111-1111-111111111502', 'accepted');

-- Insertion directe en tant que superuser pour simuler un message envoyé
-- avant l'expiration (le endpoint normal refuserait désormais cet insert).
insert into public.outing_messages (id, outing_id, sender_id, body, created_at)
values (
  '33333333-3333-3333-3333-333333333501', '22222222-2222-2222-2222-222222222501',
  '11111111-1111-1111-1111-111111111501', 'Message envoyé avant expiration', now() - interval '9 days 12 hours'
);

-- Le fil expiré doit être invisible pour le participant, même s'il a bien
-- participé à la sortie (0012_outing_messages.sql : filtrage RLS par
-- ends_at + message_retention_days).
select tests.authenticate_as('11111111-1111-1111-1111-111111111502');

select is_empty(
  $$select 1 from public.outing_messages where outing_id = '22222222-2222-2222-2222-222222222501'$$,
  'un message d''un fil expiré est invisible via RLS, même pour un participant de la sortie'
);

select throws_ok(
  $$insert into public.outing_messages (outing_id, sender_id, body)
    values ('22222222-2222-2222-2222-222222222501', '11111111-1111-1111-1111-111111111502', 'Nouveau message tardif')$$,
  'new row violates row-level security policy for table "outing_messages"',
  'nouveau message impossible sur un fil expiré'
);

-- Seul pg_cron (rôle privilégié) doit pouvoir déclencher la purge : un
-- utilisateur authentifié normal ne doit pas pouvoir l'appeler via l'RPC
-- PostgREST correspondant (cf. `revoke execute ... from public` de
-- 0019_purge_expired_outing_messages.sql).
select throws_ok(
  $$select public.purge_expired_outing_messages()$$,
  'permission denied for function purge_expired_outing_messages',
  'un utilisateur authentifié ne peut pas appeler la purge directement'
);

-- La purge réelle (0019_purge_expired_outing_messages.sql) s'exécute en
-- pratique via pg_cron sous un rôle privilégié, jamais comme un utilisateur
-- `authenticated` normal (la fonction n'a délibérément aucun `grant execute`
-- vers authenticated). On repasse donc en superuser pour cette partie, ce
-- qui permet aussi de contourner RLS et de vérifier que la ligne existe
-- toujours en base tant qu'elle n'a pas été explicitement purgée.
reset role;

select isnt_empty(
  $$select 1 from public.outing_messages where id = '33333333-3333-3333-3333-333333333501'$$,
  'avant purge : le message expiré existe toujours en base (masqué par RLS, pas supprimé)'
);

select public.purge_expired_outing_messages();

select is_empty(
  $$select 1 from public.outing_messages where id = '33333333-3333-3333-3333-333333333501'$$,
  'après purge_expired_outing_messages() : la ligne expirée est réellement supprimée, pas seulement masquée'
);

select * from finish();
rollback;
