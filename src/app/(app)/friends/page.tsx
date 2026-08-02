import { createClient } from "@/lib/supabase/server";
import { AddFriend } from "@/components/friends/add-friend";
import { FriendRequests } from "@/components/friends/friend-requests";
import { FriendList } from "@/components/friends/friend-list";
import { cn } from "@/lib/utils";
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
    <div className="mx-auto max-w-3xl space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-sm font-medium text-primary">{accepted.length} ami{accepted.length > 1 ? "s" : ""}</p>
          <h1 className="mt-1 text-3xl font-semibold tracking-tight">Amis</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Ajoute des amis pour voir leurs disponibilités et leur envoyer une invitation directe.
          </p>
        </div>
      </div>

      <AddFriend />

      <div
        className={cn(
          "grid grid-cols-1 gap-3",
          incomingRequests.length > 0 && "sm:grid-cols-[1fr_1.4fr]",
        )}
      >
        {incomingRequests.length > 0 && (
          <FriendRequests requests={incomingRequests} />
        )}
        <FriendList friends={accepted} />
      </div>
    </div>
  );
}
