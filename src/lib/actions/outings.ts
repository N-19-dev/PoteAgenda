"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import type { OutingMessage, OutingResponse, Profile } from "@/lib/supabase/types";

type CreateOutingInput = {
  title: string;
  startsAt: string;
  endsAt: string;
  location?: string;
  note?: string;
  friendIds: string[];
  groupId?: string;
  messageRetentionDays?: number;
};

type UpdateOutingInput = {
  outingId: string;
  title: string;
  startsAt: string;
  endsAt: string;
  location?: string;
  note?: string;
};

function validDate(value: string) {
  const date = new Date(value);
  return Number.isFinite(date.getTime()) ? date : null;
}

export async function createOuting(input: CreateOutingInput) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Non authentifié");

  const title = input.title.trim();
  const startsAt = validDate(input.startsAt);
  const endsAt = validDate(input.endsAt);
  if (!title || title.length > 120 || !startsAt || !endsAt || startsAt >= endsAt) {
    throw new Error("Les informations de la sortie sont invalides");
  }

  const requestedFriendIds = [...new Set(input.friendIds)].filter((id) => id !== user.id);
  const { data: friendshipRows, error: friendshipError } = await supabase
    .from("friendships")
    .select("requester_id, addressee_id")
    .eq("status", "accepted")
    .or(`requester_id.eq.${user.id},addressee_id.eq.${user.id}`);
  if (friendshipError) throw friendshipError;
  const friendIds = new Set((friendshipRows ?? []).map((row) =>
    row.requester_id === user.id ? row.addressee_id : row.requester_id,
  ));
  if (requestedFriendIds.some((id) => !friendIds.has(id))) throw new Error("Un invité n'est pas votre ami");

  let groupMemberIds: string[] = [];
  if (input.groupId) {
    const { data: group, error: groupError } = await supabase
      .from("groups").select("id").eq("id", input.groupId).single();
    if (groupError || !group) throw new Error("Groupe introuvable ou non autorisé");
    const { data: members, error: membersError } = await supabase
      .from("group_members").select("user_id").eq("group_id", group.id);
    if (membersError) throw membersError;
    groupMemberIds = (members ?? []).map((member) => member.user_id).filter((id) => id !== user.id);
  }

  const recipientIds = [...new Set([...requestedFriendIds, ...groupMemberIds])];
  if (recipientIds.length === 0) {
    throw new Error(
      input.groupId
        ? "Ce groupe n'a pas d'autre membre à inviter"
        : "Ajoutez au moins un invité ou un groupe",
    );
  }

  const messageRetentionDays = Math.min(7, Math.max(1, Math.round(input.messageRetentionDays ?? 2)));

  const { data: outing, error } = await supabase
    .from("outings")
    .insert({
      creator_id: user.id, group_id: input.groupId || null, title,
      starts_at: startsAt.toISOString(), ends_at: endsAt.toISOString(),
      location: input.location?.trim() || null, note: input.note?.trim() || null,
      message_retention_days: messageRetentionDays,
    })
    .select("id")
    .single();
  if (error) throw error;

  const { error: participantError } = await supabase.from("outing_participants").insert(
    [...new Set([user.id, ...recipientIds])].map((userId) => ({
      outing_id: outing.id, user_id: userId,
      response: userId === user.id ? "accepted" : "pending",
      responded_at: userId === user.id ? new Date().toISOString() : null,
    })),
  );
  if (participantError) throw participantError;

  revalidatePath("/agenda");
  revalidatePath("/invitations");
  revalidatePath("/groups");
  return outing.id;
}

export async function respondToOuting(outingId: string, response: OutingResponse) {
  if (response !== "accepted" && response !== "declined" && response !== "pending") {
    throw new Error("Réponse invalide");
  }
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Non authentifié");
  const { error } = await supabase.from("outing_participants")
    .update({ response, responded_at: response === "pending" ? null : new Date().toISOString() })
    .eq("outing_id", outingId).eq("user_id", user.id);
  if (error) throw error;
  revalidatePath("/agenda");
  revalidatePath("/invitations");
}

export async function updateOuting(input: UpdateOutingInput) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Non authentifié");

  const title = input.title.trim();
  const startsAt = validDate(input.startsAt);
  const endsAt = validDate(input.endsAt);
  if (!title || title.length > 120 || !startsAt || !endsAt || startsAt >= endsAt) {
    throw new Error("Les informations de la sortie sont invalides");
  }

  const { error } = await supabase.from("outings")
    .update({
      title,
      starts_at: startsAt.toISOString(),
      ends_at: endsAt.toISOString(),
      location: input.location?.trim() || null,
      note: input.note?.trim() || null,
    })
    .eq("id", input.outingId)
    .eq("creator_id", user.id)
    .is("cancelled_at", null);
  if (error) throw error;
  revalidatePath("/agenda");
  revalidatePath("/invitations");
  revalidatePath("/groups");
}

export async function remindOutingParticipant(outingId: string, userId: string) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Non authentifié");
  const { error } = await supabase.rpc("remind_outing_participant", {
    p_outing_id: outingId,
    p_user_id: userId,
  });
  if (error) throw error;
  revalidatePath("/invitations");
}

export async function setOutingConfirmed(outingId: string, confirmed: boolean) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Non authentifié");
  const { error } = await supabase.from("outings")
    .update({ confirmed_at: confirmed ? new Date().toISOString() : null })
    .eq("id", outingId)
    .eq("creator_id", user.id);
  if (error) throw error;
  revalidatePath("/agenda");
  revalidatePath("/invitations");
  revalidatePath("/groups");
}

export async function cancelOuting(outingId: string) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Non authentifié");
  const { error } = await supabase.from("outings")
    .update({ cancelled_at: new Date().toISOString() }).eq("id", outingId).eq("creator_id", user.id);
  if (error) throw error;
  revalidatePath("/agenda");
  revalidatePath("/invitations");
}

export type OutingMessageWithProfile = OutingMessage & { profile: Pick<Profile, "username" | "avatar_url"> };

export async function getOutingMessages(outingId: string): Promise<OutingMessageWithProfile[]> {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Non authentifié");
  const { data, error } = await supabase
    .from("outing_messages")
    .select("*, profile:profiles(username, avatar_url)")
    .eq("outing_id", outingId)
    .order("created_at", { ascending: false })
    .limit(200);
  if (error) throw error;
  return ((data ?? []) as OutingMessageWithProfile[]).reverse();
}

export async function sendOutingMessage(outingId: string, body: string, mentionedUserIds: string[] = []) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Non authentifié");
  const trimmed = body.trim();
  if (!trimmed || trimmed.length > 2000) throw new Error("Message invalide");
  const { error } = await supabase.from("outing_messages").insert({
    outing_id: outingId,
    sender_id: user.id,
    body: trimmed,
    mentioned_user_ids: [...new Set(mentionedUserIds)],
  });
  if (error) throw error;
}
