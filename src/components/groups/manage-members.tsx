"use client";

import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Trash2, UserPlus } from "lucide-react";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { ListRow, ListRowGroup } from "@/components/ui/list-row";
import { addGroupMember, removeGroupMember } from "@/lib/actions/groups";
import type { Profile } from "@/lib/supabase/types";

export function ManageMembers({
  groupId,
  members,
  availableFriends,
  isOwner,
  currentUserId,
}: {
  groupId: string;
  members: Profile[];
  availableFriends: Profile[];
  isOwner: boolean;
  currentUserId: string;
}) {
  const [isPending, startTransition] = useTransition();
  const router = useRouter();

  function handleAdd(userId: string) {
    startTransition(async () => {
      try {
        await addGroupMember(groupId, userId);
        toast.success("Membre ajouté");
        router.refresh();
      } catch {
        toast.error("Impossible d'ajouter ce membre");
      }
    });
  }

  function handleRemove(userId: string) {
    startTransition(async () => {
      try {
        await removeGroupMember(groupId, userId);
        toast.success(userId === currentUserId ? "Tu as quitté le groupe" : "Membre retiré");
        router.refresh();
        if (userId === currentUserId) router.push("/groups");
      } catch {
        toast.error("Action impossible");
      }
    });
  }

  return (
    <div className="space-y-6">
      <div className="space-y-2">
        <h2 className="font-mono text-xs uppercase tracking-wide text-muted-foreground">
          Membres ({members.length})
        </h2>
        <ListRowGroup>
          {members.map((m) => (
            <ListRow key={m.id}>
              <div className="flex items-center gap-2.5">
                <Avatar className="h-8 w-8">
                  <AvatarFallback className="text-xs">
                    {m.username.slice(0, 2).toUpperCase()}
                  </AvatarFallback>
                </Avatar>
                <span className="text-sm">@{m.username}</span>
              </div>
              {isOwner && m.id !== currentUserId && (
                <Button
                  variant="ghost"
                  size="icon"
                  disabled={isPending}
                  onClick={() => handleRemove(m.id)}
                  aria-label="Retirer du groupe"
                >
                  <Trash2 className="h-4 w-4 text-muted-foreground" />
                </Button>
              )}
              {m.id === currentUserId && !isOwner && (
                <Button
                  variant="ghost"
                  size="sm"
                  disabled={isPending}
                  onClick={() => handleRemove(m.id)}
                >
                  Quitter
                </Button>
              )}
            </ListRow>
          ))}
        </ListRowGroup>
      </div>

      {isOwner && (
        <div className="space-y-2">
          <h2 className="font-mono text-xs uppercase tracking-wide text-muted-foreground">
            Ajouter un ami
          </h2>
          {availableFriends.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              Tous tes amis sont déjà dans ce groupe.
            </p>
          ) : (
            <ListRowGroup>
              {availableFriends.map((f) => (
                <ListRow key={f.id}>
                  <div className="flex items-center gap-2.5">
                    <Avatar className="h-8 w-8">
                      <AvatarFallback className="text-xs">
                        {f.username.slice(0, 2).toUpperCase()}
                      </AvatarFallback>
                    </Avatar>
                    <span className="text-sm">@{f.username}</span>
                  </div>
                  <Button
                    variant="outline"
                    size="sm"
                    disabled={isPending}
                    onClick={() => handleAdd(f.id)}
                    className="gap-1.5"
                  >
                    <UserPlus className="h-3.5 w-3.5" />
                    Ajouter
                  </Button>
                </ListRow>
              ))}
            </ListRowGroup>
          )}
        </div>
      )}
    </div>
  );
}
