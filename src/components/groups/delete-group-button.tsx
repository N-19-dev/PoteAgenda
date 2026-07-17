"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { toast } from "sonner";
import { Trash2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { deleteGroup } from "@/lib/actions/groups";

export function DeleteGroupButton({ groupId, groupName }: { groupId: string; groupName: string }) {
  const [open, setOpen] = useState(false);
  const [isPending, startTransition] = useTransition();
  const router = useRouter();

  function handleDelete() {
    startTransition(async () => {
      try {
        await deleteGroup(groupId);
        toast.success("Groupe supprimé");
        router.push("/groups");
      } catch {
        toast.error("Impossible de supprimer le groupe");
      }
    });
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button variant="destructive" size="sm" className="gap-1.5" />}>
        <Trash2 className="h-4 w-4" />
        Supprimer le groupe
      </DialogTrigger>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>Supprimer « {groupName} » ?</DialogTitle>
        </DialogHeader>
        <p className="text-sm text-muted-foreground">
          Cette action est irréversible. Tous les membres perdront l&apos;accès au groupe.
        </p>
        <DialogFooter>
          <Button variant="outline" onClick={() => setOpen(false)}>
            Annuler
          </Button>
          <Button variant="destructive" disabled={isPending} onClick={handleDelete}>
            {isPending ? "Suppression..." : "Supprimer"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
