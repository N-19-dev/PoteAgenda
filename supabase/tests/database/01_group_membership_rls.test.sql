begin;
select plan(4);

select tests.create_test_user('11111111-1111-1111-1111-111111111101', 'owner_a');
select tests.create_test_user('11111111-1111-1111-1111-111111111102', 'stranger_b');

insert into public.groups (id, name, owner_id)
values ('22222222-2222-2222-2222-222222222201', 'Groupe privé A', '11111111-1111-1111-1111-111111111101');

-- Un étranger au groupe ne doit jamais pouvoir s'auto-ajouter (cf. faille
-- corrigée par 0018_fix_authz_holes.sql : l'ancienne policy acceptait
-- `user_id = auth.uid()` comme disjonction indépendante).
select tests.authenticate_as('11111111-1111-1111-1111-111111111102');

select throws_ok(
  $$insert into public.group_members (group_id, user_id, role)
    values ('22222222-2222-2222-2222-222222222201', '11111111-1111-1111-1111-111111111102', 'member')$$,
  'new row violates row-level security policy for table "group_members"',
  'un étranger ne peut pas s''auto-ajouter à un groupe qu''il ne possède pas'
);

select is(
  (select count(*)::int from public.group_members where group_id = '22222222-2222-2222-2222-222222222201'),
  0,
  'aucune ligne group_members n''a été insérée par l''étranger'
);

-- Le owner, lui, peut toujours s'insérer comme premier membre (flux légitime
-- de création de groupe : owner_id = auth.uid() au moment de l'insert).
select tests.authenticate_as('11111111-1111-1111-1111-111111111101');

select lives_ok(
  $$insert into public.group_members (group_id, user_id, role)
    values ('22222222-2222-2222-2222-222222222201', '11111111-1111-1111-1111-111111111101', 'owner')$$,
  'le owner peut s''insérer lui-même comme premier membre de son groupe'
);

-- Le owner peut aussi ajouter un tiers comme membre.
select lives_ok(
  $$insert into public.group_members (group_id, user_id, role)
    values ('22222222-2222-2222-2222-222222222201', '11111111-1111-1111-1111-111111111102', 'member')$$,
  'le owner peut ajouter un autre utilisateur comme membre'
);

select * from finish();
rollback;
