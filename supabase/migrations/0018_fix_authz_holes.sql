-- ============================================================================
-- Corrige trois failles d'autorisation trouvées en revue de sécurité :
--
-- 1. group_members_insert_owner acceptait `user_id = auth.uid()` comme
--    disjonction indépendante, donc n'importe quel utilisateur authentifié
--    connaissant un group_id pouvait s'auto-ajouter à n'importe quel groupe.
--    Le flux légitime (owner insère lui-même comme premier membre juste
--    après avoir créé le groupe) reste couvert car owner_id = auth.uid() à
--    ce moment-là : il n'est donc plus nécessaire d'avoir la disjonction.
--
-- 2. friendships_update_involved utilisait `auth.uid() in (requester_id,
--    addressee_id)` à la fois en USING et en WITH CHECK, ce qui permettait
--    au demandeur de passer lui-même le statut à 'accepted'. Seul le
--    destinataire doit pouvoir répondre à une demande.
--
-- 3. outing_participants_update_own_response ne figeait pas outing_id ni
--    user_id : un participant pouvait PATCH sa propre ligne en changeant sa
--    clé primaire vers un autre outing_id, devenant ainsi "participant" (et
--    donc lecteur) d'une sortie à laquelle il n'a jamais été invité. Un
--    trigger BEFORE UPDATE bloque tout changement d'identité de la ligne,
--    quelle que soit la policy RLS utilisée pour l'UPDATE.
-- ============================================================================

-- 1. group_members : seul le owner du groupe peut insérer des membres
--    (y compris s'insérer lui-même à la création du groupe).
drop policy "group_members_insert_owner" on public.group_members;

create policy "group_members_insert_owner"
  on public.group_members for insert
  to authenticated
  with check (
    exists (select 1 from public.groups g where g.id = group_id and g.owner_id = auth.uid())
  );

-- 2. friendships : seul le destinataire peut répondre à une demande.
drop policy "friendships_update_involved" on public.friendships;

create policy "friendships_update_addressee_responds"
  on public.friendships for update
  to authenticated
  using (addressee_id = auth.uid())
  with check (addressee_id = auth.uid());

-- 3. outing_participants : une ligne ne peut changer que `response` /
--    `responded_at`, jamais son outing_id ou son user_id.
create function public.enforce_outing_participant_identity()
returns trigger
language plpgsql
as $$
begin
  if new.outing_id <> old.outing_id or new.user_id <> old.user_id then
    raise exception 'cannot change outing_id or user_id of an outing_participants row';
  end if;
  return new;
end;
$$;

create trigger outing_participants_lock_identity
  before update on public.outing_participants
  for each row execute procedure public.enforce_outing_participant_identity();
