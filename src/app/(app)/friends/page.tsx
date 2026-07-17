import { createClient } from "@/lib/supabase/server";
import { AddFriend } from "@/components/friends/add-friend";
import { FriendRequests } from "@/components/friends/friend-requests";
import { FriendList } from "@/components/friends/friend-list";
import type { FriendshipStatus, Profile } from "@/lib/supabase/types";

interface FriendshipRow {
  id: string;
  status: FriendshipStatus;
  requester_id: string;
  addressee_id: string;
  requester: Profile;
  addressee: Profile;
}

export default async function FriendsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: friendships } = await supabase
    .from("friendships")
    .select(
      "id, status, requester_id, addressee_id, requester:profiles!friendships_requester_id_fkey(*), addressee:profiles!friendships_addressee_id_fkey(*)",
    )
    .or(`requester_id.eq.${user!.id},addressee_id.eq.${user!.id}`)
    .returns<FriendshipRow[]>();

  const rows = friendships ?? [];

  const incomingRequests = rows
    .filter((r) => r.status === "pending" && r.addressee_id === user!.id)
    .map((r) => ({ friendshipId: r.id, profile: r.requester }));

  const accepted = rows
    .filter((r) => r.status === "accepted")
    .map((r) => ({
      friendshipId: r.id,
      profile: r.requester_id === user!.id ? r.addressee : r.requester,
    }));

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold tracking-tight">Amis</h1>
        <p className="text-sm text-muted-foreground">
          Ajoute des amis pour les inviter dans tes groupes.
        </p>
      </div>

      <AddFriend />
      <FriendRequests requests={incomingRequests} />
      <FriendList friends={accepted} />
    </div>
  );
}
