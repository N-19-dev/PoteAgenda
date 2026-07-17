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

export function CreateGroupDialog() {
  const [open, setOpen] = useState(false);
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [isPending, startTransition] = useTransition();
  const router = useRouter();

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!name.trim()) return;
    startTransition(async () => {
      try {
        const group = await createGroup(name.trim(), description.trim() || null);
        toast.success("Groupe créé");
        setOpen(false);
        setName("");
        setDescription("");
        router.push(`/groups/${group.id}`);
      } catch {
        toast.error("Impossible de créer le groupe");
      }
    });
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button size="sm" className="gap-1.5" />}>
        <Plus className="h-4 w-4" />
        Nouveau groupe
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
