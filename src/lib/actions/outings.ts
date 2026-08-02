"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";
import type { OutingResponse } from "@/lib/supabase/types";

type CreateOutingInput = {
  title: string;
  startsAt: string;
  endsAt: string;
  location?: string;
  note?: string;
  friendIds: string[];
  groupId?: string;
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

  const { data: outing, error } = await supabase
    .from("outings")
    .insert({
      creator_id: user.id, group_id: input.groupId || null, title,
      starts_at: startsAt.toISOString(), ends_at: endsAt.toISOString(),
      location: input.location?.trim() || null, note: input.note?.trim() || null,
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
  if (response !== "accepted" && response !== "declined") throw new Error("Réponse invalide");
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Non authentifié");
  const { error } = await supabase.from("outing_participants")
    .update({ response, responded_at: new Date().toISOString() })
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
