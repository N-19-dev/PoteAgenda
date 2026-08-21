begin;
select plan(4);

select tests.create_test_user('11111111-1111-1111-1111-111111111401', 'owner');
select tests.create_test_user('11111111-1111-1111-1111-111111111402', 'friend_no_optin');
select tests.create_test_user('11111111-1111-1111-1111-111111111403', 'friend_with_optin');
select tests.create_test_user('11111111-1111-1111-1111-111111111404', 'not_a_friend');

insert into public.friendships (requester_id, addressee_id, status)
values
  ('11111111-1111-1111-1111-111111111401', '11111111-1111-1111-1111-111111111402', 'accepted'),
  ('11111111-1111-1111-1111-111111111401', '11111111-1111-1111-1111-111111111403', 'accepted');

insert into public.calendar_events (id, user_id, title, start_at, end_at, color, source)
values (
  '22222222-2222-2222-2222-222222222401',
  '11111111-1111-1111-1111-111111111401',
  'Rendez-vous médical confidentiel',
  now() + interval '1 hour',
  now() + interval '2 hours',
  '#000000',
  'manual'
);

-- Le owner active le partage du titre réel uniquement pour friend_with_optin.
select tests.authenticate_as('11111111-1111-1111-1111-111111111401');
insert into public.calendar_share_preferences (owner_id, viewer_id, enabled)
values ('11111111-1111-1111-1111-111111111401', '11111111-1111-1111-1111-111111111403', true);

-- Sans opt-in : le créneau est visible (occupé) mais jamais le titre.
select tests.authenticate_as('11111111-1111-1111-1111-111111111402');

select is(
  (
    select title from public.get_friends_busy_events(
      array['11111111-1111-1111-1111-111111111401']::uuid[],
      current_date,
      current_date + 1
    )
    where user_id = '11111111-1111-1111-1111-111111111401'
    limit 1
  ),
  null,
  'get_friends_busy_events ne renvoie jamais le titre sans opt-in explicite du propriétaire'
);

select isnt_empty(
  $$select 1 from public.get_friends_busy_events(
      array['11111111-1111-1111-1111-111111111401']::uuid[],
      current_date,
      current_date + 1
    )$$,
  'le créneau "occupé" reste visible même sans partage du titre'
);

-- Avec opt-in explicite pour ce viewer précis : le titre est renvoyé.
select tests.authenticate_as('11111111-1111-1111-1111-111111111403');

select is(
  (
    select title from public.get_friends_busy_events(
      array['11111111-1111-1111-1111-111111111401']::uuid[],
      current_date,
      current_date + 1
    )
    where user_id = '11111111-1111-1111-1111-111111111401'
    limit 1
  ),
  'Rendez-vous médical confidentiel',
  'le titre n''est renvoyé qu''au destinataire pour lequel le partage a été explicitement activé'
);

-- Un tiers qui n'est pas ami accepté ne voit même pas le créneau.
select tests.authenticate_as('11111111-1111-1111-1111-111111111404');

select is_empty(
  $$select 1 from public.get_friends_busy_events(
      array['11111111-1111-1111-1111-111111111401']::uuid[],
      current_date,
      current_date + 1
    )$$,
  'un utilisateur qui n''est pas ami accepté du propriétaire ne voit rien du tout'
);

select * from finish();
rollback;
