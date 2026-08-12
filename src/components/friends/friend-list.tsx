"use client";

import { useTransition } from "react";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { UserMinus, Users } from "lucide-react";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { EmptyState } from "@/components/ui/empty-state";
import { ListRow, ListRowGroup } from "@/components/ui/list-row";
import { Switch } from "@/components/ui/switch";
import { removeFriend, setCalendarSharePreference } from "@/lib/actions/friends";
import type { Profile } from "@/lib/supabase/types";

export function FriendList({
  friends,
  shareEnabledByFriend = {},
}: {
  friends: { friendshipId: string; profile: Profile }[];
  shareEnabledByFriend?: Record<string, boolean>;
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

  function handleShareToggle(friendId: string, enabled: boolean) {
    startTransition(async () => {
      try {
        await setCalendarSharePreference(friendId, enabled);
        toast.success(enabled ? "Détail des événements partagé" : "Partage désactivé");
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
        <EmptyState
          className="gap-2 py-10"
          icon={<Users className="h-7 w-7 text-muted-foreground" />}
          message="Ajoute des amis par pseudo ou email pour voir leurs disponibilités et les inviter."
        />
      ) : (
        <ListRowGroup>
          {friends.map(({ friendshipId, profile }) => (
            <ListRow key={friendshipId}>
              <Link
                href={`/agenda?friends=${profile.id}`}
                className="flex min-w-0 flex-1 items-center gap-2.5"
                aria-label={`Voir la disponibilité de @${profile.username} dans l'agenda`}
              >
                <Avatar className="h-8 w-8">
                  <AvatarFallback className="text-xs">
                    {profile.username.slice(0, 2).toUpperCase()}
                  </AvatarFallback>
                </Avatar>
                <span className="truncate text-sm">@{profile.username}</span>
              </Link>
              <div className="flex shrink-0 items-center gap-3">
                <label className="flex items-center gap-1.5 text-[10px] text-muted-foreground">
                  <span className="hidden sm:inline">Partager le détail</span>
                  <Switch
                    size="sm"
                    checked={!!shareEnabledByFriend[profile.id]}
                    onCheckedChange={(checked) => handleShareToggle(profile.id, checked)}
                    disabled={isPending}
                    aria-label={`Partager le détail de mes événements avec @${profile.username}`}
                  />
                </label>
                <Button
                  size="icon"
                  variant="ghost"
                  disabled={isPending}
                  onClick={() => handleRemove(friendshipId)}
                  aria-label="Retirer cet ami"
                >
                  <UserMinus className="h-4 w-4 text-muted-foreground" />
                </Button>
              </div>
            </ListRow>
          ))}
        </ListRowGroup>
      )}
    </div>
  );
}
