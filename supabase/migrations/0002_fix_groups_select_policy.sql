-- ============================================================================
-- Fix : un owner ne peut pas relire le groupe qu'il vient de créer, car il
-- n'est pas encore dans group_members au moment du RETURNING de l'INSERT
-- (createGroup insère d'abord dans `groups`, puis dans `group_members`).
-- ============================================================================

drop policy "groups_select_members" on public.groups;

create policy "groups_select_members"
  on public.groups for select
  to authenticated
  using (owner_id = auth.uid() or public.is_group_member(id, auth.uid()));
