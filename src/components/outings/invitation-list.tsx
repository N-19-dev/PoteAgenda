"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { format } from "date-fns";
import { fr } from "date-fns/locale";
import { Bell, Check, ChevronDown, Clock, MapPin, Pencil, Trash2, X } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { cancelOuting, remindOutingParticipant, respondToOuting, updateOuting } from "@/lib/actions/outings";
import type { Outing, OutingParticipant, Profile } from "@/lib/supabase/types";
import { DateTimeFields, dateTimePartsToISOString, isoStringToDateTimeParts, type DateTimeParts } from "./date-time-fields";

export type InvitationItem = { outing: Outing; participants: (OutingParticipant & { profile: Profile })[] };

export function InvitationList({ invitations, currentUserId }: { invitations: InvitationItem[]; currentUserId: string }) {
  const [isPending, startTransition] = useTransition();
  const [editing, setEditing] = useState<Outing | null>(null);
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const router = useRouter();

  function toggleExpanded(outingId: string) {
    setExpanded((current) => {
      const next = new Set(current);
      if (next.has(outingId)) next.delete(outingId);
      else next.add(outingId);
      return next;
    });
  }

  function respond(outingId: string, response: "accepted" | "declined" | "pending") {
    startTransition(async () => {
      try {
        await respondToOuting(outingId, response);
        toast.success(
          response === "accepted" ? "Tu viens à cette sortie" : response === "declined" ? "Réponse enregistrée" : "Réponse annulée",
        );
      } catch { toast.error("Impossible d'enregistrer ta réponse"); }
    });
  }

  function remind(outingId: string, userId: string) {
    startTransition(async () => {
      try {
        await remindOutingParticipant(outingId, userId);
        toast.success("Relance enregistrée — visible à sa prochaine visite");
        router.refresh();
      } catch {
        toast.error("Impossible de relancer");
      }
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
    const declined = participants.filter((participant) => participant.response === "declined");
    const pending = participants.filter((participant) => participant.response === "pending");
    const isExpanded = expanded.has(outing.id);
    return <article key={outing.id} className="rounded-lg border border-border bg-card p-4 shadow-sm">
      <div className="flex items-start justify-between gap-3"><div><h2 className="font-semibold">{outing.title}</h2><p className="mt-1 text-sm text-muted-foreground">{format(new Date(outing.starts_at), "EEEE d MMMM · HH:mm", { locale: fr })} – {format(new Date(outing.ends_at), "HH:mm", { locale: fr })}</p>{outing.location && <p className="mt-1 flex items-center gap-1 text-sm text-muted-foreground"><MapPin className="size-3.5" />{outing.location}</p>}</div><span className="rounded-full bg-muted px-2 py-1 text-xs text-muted-foreground">{outing.cancelled_at ? "Annulée" : `${accepted.length} présent${accepted.length > 1 ? "s" : ""}`}</span></div>
      {outing.note && <p className="mt-3 text-sm">{outing.note}</p>}
      <button
        type="button"
        onClick={() => toggleExpanded(outing.id)}
        className="mt-4 flex w-full items-center justify-between gap-2 text-left text-xs text-muted-foreground"
        aria-expanded={isExpanded}
      >
        <span><strong className="font-medium text-foreground">Présents :</strong> {accepted.map((participant) => participant.profile.username).join(", ") || "Personne"}{pending.length > 0 && ` · ${pending.length} en attente`}</span>
        <ChevronDown className={`size-3.5 shrink-0 transition-transform ${isExpanded ? "rotate-180" : ""}`} />
      </button>
      {isExpanded && (
        <div className="mt-2 space-y-1.5 rounded-md border border-border/60 bg-muted/30 p-3 text-xs">
          <ParticipantStatusRow label="Présents" icon={<Check className="size-3.5 text-primary" />} participants={accepted} />
          <ParticipantStatusRow label="Absents" icon={<X className="size-3.5 text-muted-foreground" />} participants={declined} />
          <ParticipantStatusRow
            label="En attente"
            icon={<Clock className="size-3.5 text-amber-500" />}
            participants={pending}
            remind={isCreator && !outing.cancelled_at ? (userId) => remind(outing.id, userId) : undefined}
            isPending={isPending}
          />
        </div>
      )}
      {mine?.response === "pending" && recentlyReminded(mine.reminded_at) && (
        <p className="mt-3 flex items-center gap-1.5 text-xs font-medium text-amber-600 dark:text-amber-400">
          <Bell className="size-3.5" />
          On te relance pour cette sortie !
        </p>
      )}
      {mine && !outing.cancelled_at && (
        <div className="mt-4 flex flex-wrap items-center gap-2">
          <Button size="sm" variant={mine.response === "accepted" ? "default" : "outline"} onClick={() => respond(outing.id, "accepted")} disabled={isPending}><Check />Présent</Button>
          <Button size="sm" variant={mine.response === "declined" ? "default" : "outline"} onClick={() => respond(outing.id, "declined")} disabled={isPending}><X />Absent</Button>
          {mine.response !== "pending" && (
            <Button size="sm" variant="ghost" className="text-muted-foreground" onClick={() => respond(outing.id, "pending")} disabled={isPending}>
              Annuler ma réponse
            </Button>
          )}
        </div>
      )}
      {isCreator && !outing.cancelled_at && <div className="mt-4 flex flex-wrap gap-2"><Button className="gap-1.5" size="sm" variant="outline" disabled={isPending} onClick={() => setEditing(outing)}><Pencil className="size-3.5" />Modifier</Button><Button className="gap-1.5" size="sm" variant="destructive" disabled={isPending} onClick={() => cancel(outing.id)}><Trash2 className="size-3.5" />Annuler la sortie</Button></div>}
    </article>;
  })}<EditOutingDialog outing={editing} onClose={() => setEditing(null)} isPending={isPending} startTransition={startTransition} /></div>;
}

const REMIND_COOLDOWN_MS = 12 * 60 * 60 * 1000;

function recentlyReminded(remindedAt: string | null) {
  return !!remindedAt && Date.now() - new Date(remindedAt).getTime() < REMIND_COOLDOWN_MS;
}

function ParticipantStatusRow({
  label,
  icon,
  participants,
  remind,
  isPending,
}: {
  label: string;
  icon: React.ReactNode;
  participants: (OutingParticipant & { profile: Profile })[];
  remind?: (userId: string) => void;
  isPending?: boolean;
}) {
  if (participants.length === 0) return null;
  return (
    <div className="flex items-start gap-1.5">
      {icon}
      <div className="flex-1 space-y-1">
        <span><strong className="font-medium text-foreground">{label} ({participants.length}) :</strong> {!remind && participants.map((participant) => participant.profile.username).join(", ")}</span>
        {remind && (
          <ul className="space-y-1">
            {participants.map((participant) => {
              const reminded = recentlyReminded(participant.reminded_at);
              return (
                <li key={participant.user_id} className="flex items-center justify-between gap-2">
                  <span>@{participant.profile.username}</span>
                  <button
                    type="button"
                    onClick={() => remind(participant.user_id)}
                    disabled={isPending || reminded}
                    className="flex items-center gap-1 text-[11px] font-medium text-primary hover:underline disabled:text-muted-foreground disabled:no-underline"
                  >
                    <Bell className="size-3" />
                    {reminded ? "Relancé" : "Relancer"}
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </div>
  );
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
  function openChange(open: boolean) {
    if (!open) onClose();
  }

  return (
    <Dialog open={!!outing} onOpenChange={openChange}>
      <DialogContent className="sm:max-w-lg">
        {outing && (
          <EditOutingForm
            key={outing.id}
            outing={outing}
            onClose={onClose}
            isPending={isPending}
            startTransition={startTransition}
          />
        )}
      </DialogContent>
    </Dialog>
  );
}

function EditOutingForm({
  outing,
  onClose,
  isPending,
  startTransition,
}: {
  outing: Outing;
  onClose: () => void;
  isPending: boolean;
  startTransition: React.TransitionStartFunction;
}) {
  const router = useRouter();
  const [title, setTitle] = useState(outing.title);
  const [starts, setStarts] = useState<DateTimeParts>(() => isoStringToDateTimeParts(outing.starts_at));
  const [ends, setEnds] = useState<DateTimeParts>(() => isoStringToDateTimeParts(outing.ends_at));
  const [location, setLocation] = useState(outing.location ?? "");
  const [note, setNote] = useState(outing.note ?? "");

  function submit(event: React.FormEvent) {
    event.preventDefault();
    startTransition(async () => {
      try {
        await updateOuting({
          outingId: outing.id,
          title,
          startsAt: dateTimePartsToISOString(starts),
          endsAt: dateTimePartsToISOString(ends),
          location,
          note,
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
    <form onSubmit={submit}>
      <DialogHeader><DialogTitle>Modifier la sortie</DialogTitle></DialogHeader>
      <div className="space-y-4 py-5">
        <div className="space-y-1.5"><Label htmlFor="edit-outing-title">Nom</Label><Input id="edit-outing-title" value={title} onChange={(e) => setTitle(e.target.value)} required /></div>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <DateTimeFields legend="Début" idPrefix="edit-outing-start" value={starts} onChange={setStarts} />
          <DateTimeFields legend="Fin" idPrefix="edit-outing-end" value={ends} onChange={setEnds} />
        </div>
        <div className="space-y-1.5"><Label htmlFor="edit-outing-location">Lieu</Label><Input id="edit-outing-location" value={location} onChange={(e) => setLocation(e.target.value)} /></div>
        <div className="space-y-1.5"><Label htmlFor="edit-outing-note">Note</Label><Textarea id="edit-outing-note" value={note} onChange={(e) => setNote(e.target.value)} /></div>
      </div>
      <DialogFooter><Button type="submit" disabled={isPending}>Enregistrer</Button></DialogFooter>
    </form>
  );
}
