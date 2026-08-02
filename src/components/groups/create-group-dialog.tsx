"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { Plus } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { createGroup } from "@/lib/actions/groups";
import { toast } from "sonner";
import type { Profile } from "@/lib/supabase/types";

export function CreateGroupDialog({
  variant = "button",
  friends = [],
}: {
  variant?: "button" | "tile";
  friends?: Profile[];
}) {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [memberIds, setMemberIds] = useState<string[]>([]);
  const [isPending, startTransition] = useTransition();
  const router = useRouter();

  function toggleMember(id: string) {
    setMemberIds((ids) => (ids.includes(id) ? ids.filter((memberId) => memberId !== id) : [...ids, id]));
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim()) return;
    startTransition(async () => {
      try {
        const group = await createGroup(name.trim(), description.trim() || null, memberIds);
        toast.success("Groupe créé");
        setOpen(false);
        setName("");
        setDescription("");
        setMemberIds([]);
        router.push(`/groups/${group.id}`);
      } catch {
        toast.error("Impossible de créer le groupe");
      }
    });
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger
        render={
          variant === "tile" ? (
            <button
              type="button"
              className="flex h-full min-h-[88px] w-full flex-col items-center justify-center gap-1.5 rounded-xl border border-dashed border-border/60 text-muted-foreground transition-colors hover:border-primary/50 hover:text-foreground"
            />
          ) : (
            <Button size="sm" className="gap-1.5" />
          )
        }
      >
        <Plus className="h-4 w-4" />
        {variant === "tile" ? (
          <span className="font-mono text-xs uppercase tracking-wide">Nouveau groupe</span>
        ) : (
          "Nouveau groupe"
        )}
      </DialogTrigger>
      <DialogContent>
        <form onSubmit={handleSubmit}>
          <DialogHeader>
            <DialogTitle>Créer un groupe</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 py-4">
            <div className="space-y-1.5">
              <Label htmlFor="group-name">Nom</Label>
              <Input
                id="group-name"
                placeholder="Week-end Bretagne"
                value={name}
                onChange={(e) => setName(e.target.value)}
                autoFocus
              />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="group-description">Description (optionnel)</Label>
              <Textarea
                id="group-description"
                placeholder="On cherche un week-end où tout le monde est libre"
                value={description}
                onChange={(e) => setDescription(e.target.value)}
              />
            </div>
            {friends.length > 0 && (
              <fieldset className="space-y-2">
                <legend className="text-sm font-medium">Ajouter des membres (optionnel)</legend>
                <div className="grid grid-cols-1 gap-1.5 sm:grid-cols-2">
                  {friends.map((friend) => (
                    <label
                      key={friend.id}
                      className="flex cursor-pointer items-center gap-2 rounded-md border border-border px-3 py-2 text-sm hover:bg-muted"
                    >
                      <input
                        type="checkbox"
                        checked={memberIds.includes(friend.id)}
                        onChange={() => toggleMember(friend.id)}
                        className="accent-primary"
                      />
                      {friend.username}
                    </label>
                  ))}
                </div>
              </fieldset>
            )}
          </div>
          <DialogFooter>
            <Button type="submit" disabled={isPending || !name.trim()}>
              {isPending ? "Création..." : "Créer"}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
