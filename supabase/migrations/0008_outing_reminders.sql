-- Relance légère pour les invitations en attente : le créateur d'une sortie
-- peut marquer un participant "relancé". Aucune notification push/email —
-- l'invité voit simplement l'indice la prochaine fois qu'il ouvre
-- /invitations. La colonne n'est modifiable que via la fonction ci-dessous
-- (SECURITY DEFINER), pas via une policy RLS large sur outing_participants,
-- pour ne pas laisser le créateur modifier response/responded_at d'autrui.

alter table public.outing_participants
  add column reminded_at timestamptz;

create function public.remind_outing_participant(p_outing_id uuid, p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.outings o
    where o.id = p_outing_id and o.creator_id = auth.uid() and o.cancelled_at is null
  ) then
    raise exception 'not authorized';
  end if;

  update public.outing_participants
  set reminded_at = now()
  where outing_id = p_outing_id
    and user_id = p_user_id
    and response = 'pending';
end;
$$;

grant execute on function public.remind_outing_participant(uuid, uuid) to authenticated;
