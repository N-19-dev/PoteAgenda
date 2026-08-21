-- Helpers pour les tests pgTAP : créer un utilisateur de test minimal dans
-- auth.users (déclenche public.handle_new_user -> profil créé
-- automatiquement) et basculer la session courante comme si elle était
-- authentifiée en tant que cet utilisateur, pour exercer les policies RLS
-- exactement comme le ferait PostgREST en production.
--
-- Volontairement pas de begin/rollback ici : ces fonctions doivent persister
-- (schema `tests`) pour être réutilisées par chaque fichier de test suivant,
-- qui lui s'exécute dans sa propre transaction annulée à la fin.

create schema if not exists tests;

-- Les fonctions de ce schéma doivent rester appelables même après avoir
-- basculé le rôle courant sur `authenticated` (tests.authenticate_as change
-- justement de rôle en cours de transaction, pour enchaîner plusieurs
-- identités simulées dans un même test).
grant usage on schema tests to authenticated, anon, service_role;
alter default privileges in schema tests grant execute on functions to authenticated, anon, service_role;

create or replace function tests.create_test_user(p_id uuid, p_username text)
returns void
language sql
as $$
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at
  )
  values (
    p_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated',
    'authenticated',
    p_username || '@example.test',
    crypt('password123', gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}',
    jsonb_build_object('username', p_username),
    now(),
    now()
  );
$$;

-- Bascule le rôle courant sur `authenticated` (comme PostgREST le fait par
-- requête) et pose le JWT simulé pour que auth.uid() renvoie p_id. Ne doit
-- être appelée qu'après avoir créé toutes les données de fixture qui
-- nécessitent les privilèges superuser (le rôle `authenticated` est
-- volontairement restreint par les policies RLS testées ici).
create or replace function tests.authenticate_as(p_id uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_id, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$;

-- Filet de sécurité pour une exécution idempotente (`create or replace`
-- ci-dessus ne redéclenche pas ALTER DEFAULT PRIVILEGES sur un schéma déjà
-- initialisé lors d'une relance de ce fichier).
grant execute on all functions in schema tests to authenticated, anon, service_role;

-- `supabase test db` (pg_prove) exécute tous les .sql de ce dossier et
-- s'attend à une sortie TAP valide pour chacun. Ce fichier n'est pas un test
-- à proprement parler (pas de begin/rollback : le schéma `tests` doit
-- persister pour les fichiers suivants), d'où ce plan trivial en une seule
-- assertion plutôt qu'un bloc transactionnel comme les autres fichiers.
select plan(1);
select pass('schéma tests et fonctions helper créés');
select * from finish();
