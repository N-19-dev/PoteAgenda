"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function createGroup(name: string, description: string | null, memberIds: string[] = []) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Non authentifié");

  const { data: group, error } = await supabase
    .from("groups")
    .insert({ name, description, owner_id: user.id })
    .select()
    .single();
  if (error) throw error;

  const otherMemberIds = [...new Set(memberIds)].filter((id) => id !== user.id);
  const { error: memberError } = await supabase.from("group_members").insert([
    { group_id: group.id, user_id: user.id, role: "owner" },
    ...otherMemberIds.map((userId) => ({ group_id: group.id, user_id: userId, role: "member" as const })),
  ]);
  if (memberError) throw memberError;

  revalidatePath("/groups");
  return group;
}

export async function addGroupMember(groupId: string, userId: string) {
  const supabase = await createClient();
  const { error } = await supabase
    .from("group_members")
    .insert({ group_id: groupId, user_id: userId, role: "member" });
  if (error) throw error;
  revalidatePath(`/groups/${groupId}`);
  revalidatePath(`/groups/${groupId}/settings`);
}

export async function removeGroupMember(groupId: string, userId: string) {
  const supabase = await createClient();
  const { error } = await supabase
    .from("group_members")
    .delete()
    .eq("group_id", groupId)
    .eq("user_id", userId);
  if (error) throw error;
  revalidatePath(`/groups/${groupId}`);
  revalidatePath(`/groups/${groupId}/settings`);
}

export async function deleteGroup(groupId: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("groups").delete().eq("id", groupId);
  if (error) throw error;
  revalidatePath("/groups");
}
