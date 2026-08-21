begin;
select plan(4);

select tests.create_test_user('11111111-1111-1111-1111-111111111301', 'organizer');
select tests.create_test_user('11111111-1111-1111-1111-111111111302', 'invitee');

insert into public.outings (id, creator_id, title, starts_at, ends_at)
values (
  '22222222-2222-2222-2222-222222222301', '11111111-1111-1111-1111-111111111301',
  'Sortie A', now() + interval '1 day', now() + interval '1 day 2 hours'
);
insert into public.outings (id, creator_id, title, starts_at, ends_at)
values (
  '22222222-2222-2222-2222-222222222302', '11111111-1111-1111-1111-111111111301',
  'Sortie B (privée, jamais invité)', now() + interval '2 days', now() + interval '2 days 2 hours'
);

insert into public.outing_participants (outing_id, user_id, response)
values ('22222222-2222-2222-2222-222222222301', '11111111-1111-1111-1111-111111111302', 'pending');
insert into public.outing_participants (outing_id, user_id, response)
values ('22222222-2222-2222-2222-222222222301', '11111111-1111-1111-1111-111111111301', 'accepted');

-- Le participant répond normalement à SA sortie : autorisé.
select tests.authenticate_as('11111111-1111-1111-1111-111111111302');

select lives_ok(
  $$update public.outing_participants
    set response = 'accepted', responded_at = now()
    where outing_id = '22222222-2222-2222-2222-222222222301'
      and user_id = '11111111-1111-1111-1111-111111111302'$$,
  'un participant peut répondre normalement (response/responded_at) à sa propre invitation'
);

-- Retargeting : le participant tente de faire pointer SA ligne vers une
-- sortie à laquelle il n'a jamais été invité (cf. faille corrigée par
-- 0018_fix_authz_holes.sql : la policy update ne figeait ni outing_id ni
-- user_id, donc PATCH pouvait déplacer la ligne vers un outing_id arbitraire
-- et devenir "participant" - donc lecteur - d'une sortie non invitée).
select throws_ok(
  $$update public.outing_participants
    set outing_id = '22222222-2222-2222-2222-222222222302'
    where outing_id = '22222222-2222-2222-2222-222222222301'
      and user_id = '11111111-1111-1111-1111-111111111302'$$,
  'cannot change outing_id or user_id of an outing_participants row',
  'un participant ne peut pas retargeter sa ligne vers une autre sortie'
);

select is(
  (select count(*)::int from public.outing_participants where outing_id = '22222222-2222-2222-2222-222222222302'),
  0,
  'la sortie B n''a toujours aucun participant après la tentative de retargeting'
);

-- Confirme que même en gardant le même outing_id, changer user_id (usurper
-- l'identité d'un autre participant supposé) est aussi bloqué.
select throws_ok(
  $$update public.outing_participants
    set user_id = '11111111-1111-1111-1111-111111111301'
    where outing_id = '22222222-2222-2222-2222-222222222301'
      and user_id = '11111111-1111-1111-1111-111111111302'$$,
  'cannot change outing_id or user_id of an outing_participants row',
  'un participant ne peut pas usurper la ligne d''un autre participant via user_id'
);

select * from finish();
rollback;
