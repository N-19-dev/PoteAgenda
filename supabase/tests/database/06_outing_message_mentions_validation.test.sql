begin;
select plan(3);

select tests.create_test_user('11111111-1111-1111-1111-111111111601', 'organizer');
select tests.create_test_user('11111111-1111-1111-1111-111111111602', 'participant');
select tests.create_test_user('11111111-1111-1111-1111-111111111603', 'not_invited');

insert into public.outings (id, creator_id, title, starts_at, ends_at)
values (
  '22222222-2222-2222-2222-222222222601', '11111111-1111-1111-1111-111111111601',
  'Sortie avec mentions', now() + interval '1 day', now() + interval '1 day 2 hours'
);
insert into public.outing_participants (outing_id, user_id, response)
values ('22222222-2222-2222-2222-222222222601', '11111111-1111-1111-1111-111111111602', 'accepted');

select tests.authenticate_as('11111111-1111-1111-1111-111111111602');

-- Mentionner un participant réel (ou le créateur) : autorisé.
select lives_ok(
  $$insert into public.outing_messages (outing_id, sender_id, body, mentioned_user_ids)
    values (
      '22222222-2222-2222-2222-222222222601', '11111111-1111-1111-1111-111111111602',
      '@organizer peux-tu confirmer ?', array['11111111-1111-1111-1111-111111111601']::uuid[]
    )$$,
  'mentionner un participant/créateur réel de la sortie est autorisé'
);

-- Mentionner quelqu'un qui n'a jamais été invité à cette sortie : refusé
-- (cf. 0020_validate_outing_message_mentions.sql).
select throws_ok(
  $$insert into public.outing_messages (outing_id, sender_id, body, mentioned_user_ids)
    values (
      '22222222-2222-2222-2222-222222222601', '11111111-1111-1111-1111-111111111602',
      'test', array['11111111-1111-1111-1111-111111111603']::uuid[]
    )$$,
  'mentioned_user_ids must reference a participant or the creator of the outing',
  'mentionner un utilisateur non invité à la sortie est refusé'
);

select is(
  (select count(*)::int from public.outing_messages where body = 'test'),
  0,
  'le message avec mention invalide n''a pas été inséré'
);

select * from finish();
rollback;
