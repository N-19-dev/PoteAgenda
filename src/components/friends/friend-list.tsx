"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { UserMinus, Users } from "lucide-react";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { ListRow, ListRowGroup } from "@/components/ui/list-row";
import { removeFriend } from "@/lib/actions/friends";
import type { Profile } from "@/lib/supabase/types";

export function FriendList({
  friends,
}: {
  friends: { friendshipId: string; profile: Profile }[];
}) {
  const [isPending, startTransition] = useTransition();
  const router = useRouter();

  function handleRemove(friendshipId: string) {
    startTransition(async () => {
      try {
        await removeFriend(friendshipId);
        toast.success("Ami retiré");
        router.refresh();
      } catch {
        toast.error("Action impossible");
      }
    });
  }

  return (
    <div className="space-y-2">
      <h2 className="font-mono text-xs uppercase tracking-wide text-muted-foreground">
        Amis ({friends.length})
      </h2>
      {friends.length === 0 ? (
        <div className="flex flex-col items-center gap-2 rounded-lg border border-dashed border-border bg-card py-10 text-center">
          <Users className="h-7 w-7 text-muted-foreground" />
          <p className="text-sm text-muted-foreground">
            Ajoute des amis par pseudo ou email pour créer des groupes.
          </p>
        </div>
      ) : (
        <ListRowGroup>
          {friends.map(({ friendshipId, profile }) => (
            <ListRow key={friendshipId}>
              <div className="flex items-center gap-2.5">
                <Avatar className="h-8 w-8">
                  <AvatarFallback className="text-xs">
                    {profile.username.slice(0, 2).toUpperCase()}
                  </AvatarFallback>
                </Avatar>
                <span className="text-sm">@{profile.username}</span>
              </div>
              <Button
                size="icon"
                variant="ghost"
                disabled={isPending}
                onClick={() => handleRemove(friendshipId)}
                aria-label="Retirer cet ami"
              >
                <UserMinus className="h-4 w-4 text-muted-foreground" />
              </Button>
            </ListRow>
          ))}
        </ListRowGroup>
      )}
    </div>
  );
}
