"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Check, X } from "lucide-react";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { ListRow, ListRowGroup } from "@/components/ui/list-row";
import { respondToFriendRequest } from "@/lib/actions/friends";
import type { Profile } from "@/lib/supabase/types";

export function FriendRequests({
  requests,
}: {
  requests: { friendshipId: string; profile: Profile }[];
}) {
  const [isPending, startTransition] = useTransition();
  const router = useRouter();

  function respond(friendshipId: string, accept: boolean) {
    startTransition(async () => {
      try {
        await respondToFriendRequest(friendshipId, accept);
        toast.success(accept ? "Ami ajouté" : "Demande refusée");
        router.refresh();
      } catch {
        toast.error("Action impossible");
      }
    });
  }

  if (requests.length === 0) return null;

  return (
    <div className="space-y-2">
      <h2 className="font-mono text-xs uppercase tracking-wide text-muted-foreground">
        Demandes reçues ({requests.length})
      </h2>
      <ListRowGroup>
        {requests.map(({ friendshipId, profile }) => (
          <ListRow key={friendshipId}>
            <div className="flex items-center gap-2.5">
              <Avatar className="h-8 w-8">
                <AvatarFallback className="text-xs">
                  {profile.username.slice(0, 2).toUpperCase()}
                </AvatarFallback>
              </Avatar>
              <span className="text-sm">@{profile.username}</span>
            </div>
            <div className="flex gap-1.5">
              <Button
                size="icon"
                variant="outline"
                disabled={isPending}
                onClick={() => respond(friendshipId, true)}
                aria-label="Accepter"
              >
                <Check className="h-4 w-4" />
              </Button>
              <Button
                size="icon"
                variant="ghost"
                disabled={isPending}
                onClick={() => respond(friendshipId, false)}
                aria-label="Refuser"
              >
                <X className="h-4 w-4" />
              </Button>
            </div>
          </ListRow>
        ))}
      </ListRowGroup>
    </div>
  );
}
