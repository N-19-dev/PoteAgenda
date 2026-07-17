"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Check, X } from "lucide-react";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
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
      <h2 className="text-sm font-medium text-muted-foreground">
        Demandes reçues ({requests.length})
      </h2>
      <ul className="space-y-1.5">
        {requests.map(({ friendshipId, profile }) => (
          <li
            key={friendshipId}
            className="flex items-center justify-between rounded-lg border border-border bg-card px-3 py-2"
          >
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
          </li>
        ))}
      </ul>
    </div>
  );
}
