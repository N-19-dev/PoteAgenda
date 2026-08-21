-- Complète 0013_outing_message_mentions.sql, qui documentait explicitement
-- l'absence de validation serveur des UUID de `mentioned_user_ids` comme un
-- choix assumé ("confort d'UI, pas une frontière de sécurité"). On ajoute
-- ici une validation réelle : chaque id mentionné doit être un participant
-- (ou le créateur) de la sortie concernée, ce qui correspond de toute façon
-- à ce que fait déjà le client (la liste de sélection ne propose que les
-- participants chargés via outing_participants).
--
-- Ceci ne rétro-purge pas les lignes existantes ni les ids résiduels après
-- suppression de compte (cf. commentaire de 0014_delete_own_account.sql) :
-- ce résidu reste sans conséquence, aucune policy ne lit `mentioned_user_ids`
-- comme source d'autorisation.

create function public.validate_outing_message_mentions()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if exists (
    select 1
    from unnest(new.mentioned_user_ids) as mentioned_id
    where not exists (
      select 1 from public.outing_participants p
      where p.outing_id = new.outing_id and p.user_id = mentioned_id
    )
    and not exists (
      select 1 from public.outings o
      where o.id = new.outing_id and o.creator_id = mentioned_id
    )
  ) then
    raise exception 'mentioned_user_ids must reference a participant or the creator of the outing';
  end if;
  return new;
end;
$$;

create trigger outing_messages_validate_mentions
  before insert or update of mentioned_user_ids on public.outing_messages
  for each row execute procedure public.validate_outing_message_mentions();
