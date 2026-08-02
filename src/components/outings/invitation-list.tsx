"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { format } from "date-fns";
import { fr } from "date-fns/locale";
import { Check, MapPin, Pencil, Trash2, X } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { cancelOuting, respondToOuting, updateOuting } from "@/lib/actions/outings";
import type { Outing, OutingParticipant, Profile } from "@/lib/supabase/types";

export type InvitationItem = { outing: Outing; participants: (OutingParticipant & { profile: Profile })[] };

export function InvitationList({ invitations, currentUserId }: { invitations: InvitationItem[]; currentUserId: string }) {
  const [isPending, startTransition] = useTransition();
  const [editing, setEditing] = useState<Outing | null>(null);
  const router = useRouter();

  function respond(outingId: string, response: "accepted" | "declined") {
    startTransition(async () => {
      try { await respondToOuting(outingId, response); toast.success(response === "accepted" ? "Tu viens à cette sortie" : "Réponse enregistrée"); }
      catch { toast.error("Impossible d'enregistrer ta réponse"); }
    });
  }

  function cancel(outingId: string) {
    if (!window.confirm("Annuler cette sortie pour tous les invités ?")) return;
    startTransition(async () => {
      try {
        await cancelOuting(outingId);
        toast.success("Sortie annulée");
        router.refresh();
      } catch {
        toast.error("Impossible d'annuler cette sortie");
      }
    });
  }

  if (!invitations.length) return <div className="rounded-lg border border-dashed border-border p-7 text-center text-sm text-muted-foreground">Aucune invitation pour le moment.</div>;
  return <div className="space-y-3">{invitations.map(({ outing, participants }) => {
    const mine = participants.find((participant) => participant.user_id === currentUserId);
    const isCreator = outing.creator_id === currentUserId;
    const accepted = participants.filter((participant) => participant.response === "accepted");
    const pending = participants.filter((participant) => participant.response === "pending");
    return <article key={outing.id} className="rounded-lg border border-border bg-card p-4 shadow-sm">
      <div className="flex items-start justify-between gap-3"><div><h2 className="font-semibold">{outing.title}</h2><p className="mt-1 text-sm text-muted-foreground">{format(new Date(outing.starts_at), "EEEE d MMMM · HH:mm", { locale: fr })} – {format(new Date(outing.ends_at), "HH:mm", { locale: fr })}</p>{outing.location && <p className="mt-1 flex items-center gap-1 text-sm text-muted-foreground"><MapPin className="size-3.5" />{outing.location}</p>}</div><span className="rounded-full bg-muted px-2 py-1 text-xs text-muted-foreground">{outing.cancelled_at ? "Annulée" : `${accepted.length} présent${accepted.length > 1 ? "s" : ""}`}</span></div>
      {outing.note && <p className="mt-3 text-sm">{outing.note}</p>}
      <p className="mt-4 text-xs text-muted-foreground"><strong className="font-medium text-foreground">Présents :</strong> {accepted.map((participant) => participant.profile.username).join(", ") || "Personne"}{pending.length > 0 && ` · ${pending.length} en attente`}</p>
      {mine?.response === "pending" && !outing.cancelled_at && <div className="mt-4 flex gap-2"><Button size="sm" onClick={() => respond(outing.id, "accepted")} disabled={isPending}><Check />Présent</Button><Button size="sm" variant="outline" onClick={() => respond(outing.id, "declined")} disabled={isPending}><X />Absent</Button></div>}
      {mine?.response !== "pending" && !outing.cancelled_at && <p className="mt-4 text-sm font-medium text-primary">{mine?.response === "accepted" ? "Tu participes" : "Tu ne participes pas"}</p>}
      {isCreator && !outing.cancelled_at && <div className="mt-4 flex flex-wrap gap-2"><Button className="gap-1.5" size="sm" variant="outline" disabled={isPending} onClick={() => setEditing(outing)}><Pencil className="size-3.5" />Modifier</Button><Button className="gap-1.5" size="sm" variant="destructive" disabled={isPending} onClick={() => cancel(outing.id)}><Trash2 className="size-3.5" />Annuler la sortie</Button></div>}
    </article>;
  })}<EditOutingDialog outing={editing} onClose={() => setEditing(null)} isPending={isPending} startTransition={startTransition} /></div>;
}

function toDateTimeLocal(value: string) {
  const date = new Date(value);
  const offset = date.getTimezoneOffset() * 60_000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 16);
}

function EditOutingDialog({
  outing,
  onClose,
  isPending,
  startTransition,
}: {
  outing: Outing | null;
  onClose: () => void;
  isPending: boolean;
  startTransition: React.TransitionStartFunction;
}) {
  const router = useRouter();

  function openChange(open: boolean) {
    if (!open) onClose();
  }

  function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!outing) return;
    const form = new FormData(event.currentTarget as HTMLFormElement);
    startTransition(async () => {
      try {
        await updateOuting({
          outingId: outing.id,
          title: String(form.get("title") ?? ""),
          startsAt: new Date(String(form.get("startsAt") ?? "")).toISOString(),
          endsAt: new Date(String(form.get("endsAt") ?? "")).toISOString(),
          location: String(form.get("location") ?? ""),
          note: String(form.get("note") ?? ""),
        });
        toast.success("Sortie mise à jour");
        onClose();
        router.refresh();
      } catch (error) {
        toast.error(error instanceof Error ? error.message : "Impossible de modifier la sortie");
      }
    });
  }

  return (
    <Dialog open={!!outing} onOpenChange={openChange}>
      <DialogContent className="sm:max-w-lg">
        <form onSubmit={submit}>
          <DialogHeader><DialogTitle>Modifier la sortie</DialogTitle></DialogHeader>
          <div className="space-y-4 py-5">
            <div className="space-y-1.5"><Label htmlFor="edit-outing-title">Nom</Label><Input id="edit-outing-title" name="title" defaultValue={outing?.title} required /></div>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <div className="space-y-1.5"><Label htmlFor="edit-outing-start">Début</Label><Input id="edit-outing-start" name="startsAt" type="datetime-local" defaultValue={outing ? toDateTimeLocal(outing.starts_at) : ""} required /></div>
              <div className="space-y-1.5"><Label htmlFor="edit-outing-end">Fin</Label><Input id="edit-outing-end" name="endsAt" type="datetime-local" defaultValue={outing ? toDateTimeLocal(outing.ends_at) : ""} required /></div>
            </div>
            <div className="space-y-1.5"><Label htmlFor="edit-outing-location">Lieu</Label><Input id="edit-outing-location" name="location" defaultValue={outing?.location ?? ""} /></div>
            <div className="space-y-1.5"><Label htmlFor="edit-outing-note">Note</Label><Textarea id="edit-outing-note" name="note" defaultValue={outing?.note ?? ""} /></div>
          </div>
          <DialogFooter><Button type="submit" disabled={isPending}>Enregistrer</Button></DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
