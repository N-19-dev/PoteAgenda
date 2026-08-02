"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function searchProfiles(query: string) {
  if (query.trim().length < 2) return [];
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("search_profiles", { p_query: query.trim() });
  if (error) throw error;
  return data ?? [];
}

export async function sendFriendRequest(addresseeId: string) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Non authentifié");

  const { error } = await supabase
    .from("friendships")
    .insert({ requester_id: user.id, addressee_id: addresseeId, status: "pending" });
  if (error) throw error;
  revalidatePath("/friends");
}

export async function respondToFriendRequest(friendshipId: string, accept: boolean) {
  const supabase = await createClient();
  const { error } = await supabase
    .from("friendships")
    .update({ status: accept ? "accepted" : "declined" })
    .eq("id", friendshipId);
  if (error) throw error;
  revalidatePath("/friends");
}

export async function removeFriend(friendshipId: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("friendships").delete().eq("id", friendshipId);
  if (error) throw error;
  revalidatePath("/friends");
}

export async function setCalendarSharePreference(friendId: string, enabled: boolean) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Non authentifié");

  const { data: friendshipRows, error: friendshipError } = await supabase
    .from("friendships")
    .select("id")
    .eq("status", "accepted")
    .or(
      `and(requester_id.eq.${user.id},addressee_id.eq.${friendId}),and(requester_id.eq.${friendId},addressee_id.eq.${user.id})`,
    )
    .limit(1);
  if (friendshipError) throw friendshipError;
  if (!friendshipRows || friendshipRows.length === 0) throw new Error("Cette personne n'est pas ton amie");

  const { error } = await supabase
    .from("calendar_share_preferences")
    .upsert({ owner_id: user.id, viewer_id: friendId, enabled }, { onConflict: "owner_id,viewer_id" });
  if (error) throw error;
  revalidatePath("/friends");
}
