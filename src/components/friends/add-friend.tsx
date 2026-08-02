"use client";

import { useEffect, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Search, UserPlus } from "lucide-react";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { ListRow, ListRowGroup } from "@/components/ui/list-row";
import { searchProfiles, sendFriendRequest } from "@/lib/actions/friends";
import type { Profile } from "@/lib/supabase/types";

export function AddFriend() {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<Profile[]>([]);
  const [isPending, startTransition] = useTransition();
  const router = useRouter();

  useEffect(() => {
    const handle = setTimeout(() => {
      if (query.trim().length < 2) {
        setResults([]);
        return;
      }
      startTransition(async () => {
        try {
          const data = await searchProfiles(query);
          setResults(data);
        } catch {
          toast.error("Recherche impossible");
        }
      });
    }, 300);
    return () => clearTimeout(handle);
  }, [query]);

  function handleAdd(userId: string) {
    startTransition(async () => {
      try {
        await sendFriendRequest(userId);
        toast.success("Demande envoyée");
        setResults((r) => r.filter((p) => p.id !== userId));
        router.refresh();
      } catch {
        toast.error("Impossible d'envoyer la demande");
      }
    });
  }

  return (
    <div className="space-y-2">
      <div className="relative">
        <Search className="absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Pseudo ou email..."
          className="pl-8"
        />
      </div>

      {results.length > 0 && (
        <ListRowGroup>
          {results.map((p) => (
            <ListRow key={p.id}>
              <div className="flex items-center gap-2.5">
                <Avatar className="h-8 w-8">
                  <AvatarFallback className="text-xs">
                    {p.username.slice(0, 2).toUpperCase()}
                  </AvatarFallback>
                </Avatar>
                <span className="text-sm">@{p.username}</span>
              </div>
              <Button
                size="sm"
                variant="outline"
                disabled={isPending}
                onClick={() => handleAdd(p.id)}
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
  );
}
