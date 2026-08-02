import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { ManageMembers } from "@/components/groups/manage-members";
import { DeleteGroupButton } from "@/components/groups/delete-group-button";
import type { Profile } from "@/lib/supabase/types";

interface PageProps {
  params: Promise<{ groupId: string }>;
}

export default async function GroupSettingsPage({ params }: PageProps) {
  const { groupId } = await params;
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: group } = await supabase.from("groups").select("*").eq("id", groupId).single();
  if (!group || !user) notFound();

  const { data: memberRows } = await supabase
    .from("group_members")
    .select("user_id, profiles:profiles(*)")
    .eq("group_id", groupId)
    .returns<{ user_id: string; profiles: Profile }[]>();

  const members: Profile[] = (memberRows ?? []).map((row) => row.profiles).filter(Boolean);
  const memberIds = new Set(members.map((m) => m.id));

  const { data: friendRows } = await supabase
    .from("friendships")
    .select(
      "requester_id, addressee_id, requester:profiles!friendships_requester_id_fkey(*), addressee:profiles!friendships_addressee_id_fkey(*)",
    )
    .eq("status", "accepted")
    .or(`requester_id.eq.${user.id},addressee_id.eq.${user.id}`)
    .returns<{ requester_id: string; addressee_id: string; requester: Profile; addressee: Profile }[]>();

  const availableFriends: Profile[] = (friendRows ?? [])
    .map((row) => (row.requester_id === user.id ? row.addressee : row.requester))
    .filter((p) => p && !memberIds.has(p.id));

  const isOwner = group.owner_id === user.id;

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <div className="flex items-center justify-between">
        <Link
          href={`/groups/${groupId}`}
          className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
        >
          <ArrowLeft className="h-4 w-4" />
          {group.name}
        </Link>
      </div>

      <h1 className="text-2xl font-semibold tracking-tight">Réglages du groupe</h1>

      <ManageMembers
        groupId={groupId}
        members={members}
        availableFriends={availableFriends}
        isOwner={isOwner}
        currentUserId={user.id}
      />

      {isOwner && (
        <div className="border-t border-border pt-4">
          <DeleteGroupButton groupId={groupId} groupName={group.name} />
        </div>
      )}
    </div>
  );
}
