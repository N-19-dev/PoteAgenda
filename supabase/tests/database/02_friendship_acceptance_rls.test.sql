begin;
select plan(3);

select tests.create_test_user('11111111-1111-1111-1111-111111111201', 'requester');
select tests.create_test_user('11111111-1111-1111-1111-111111111202', 'addressee');

insert into public.friendships (id, requester_id, addressee_id, status)
values (
  '22222222-2222-2222-2222-222222222202',
  '11111111-1111-1111-1111-111111111201',
  '11111111-1111-1111-1111-111111111202',
  'pending'
);

-- Le demandeur ne doit jamais pouvoir accepter sa propre demande (cf. faille
-- corrigée par 0018_fix_authz_holes.sql : l'ancienne policy autorisait
-- `auth.uid() in (requester_id, addressee_id)` en WITH CHECK).
select tests.authenticate_as('11111111-1111-1111-1111-111111111201');

-- Une UPDATE dont le USING RLS exclut la ligne ne lève pas d'exception : elle
-- affecte silencieusement 0 ligne (contrairement à un WITH CHECK violé sur
-- une ligne par ailleurs visible). On l'exécute donc "à vide" et on vérifie
-- l'absence d'effet via le statut, ci-dessous.
update public.friendships set status = 'accepted'
where id = '22222222-2222-2222-2222-222222222202';

select is(
  (select status::text from public.friendships where id = '22222222-2222-2222-2222-222222222202'),
  'pending',
  'le statut reste pending après la tentative du demandeur'
);

-- Seul le destinataire peut répondre.
select tests.authenticate_as('11111111-1111-1111-1111-111111111202');

select lives_ok(
  $$update public.friendships set status = 'accepted' where id = '22222222-2222-2222-2222-222222222202'$$,
  'le destinataire peut accepter la demande'
);

select is(
  (select status::text from public.friendships where id = '22222222-2222-2222-2222-222222222202'),
  'accepted',
  'le statut passe bien à accepted après la réponse du destinataire'
);

select * from finish();
rollback;
