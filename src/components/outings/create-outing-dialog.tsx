"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { CalendarPlus } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { createOuting } from "@/lib/actions/outings";
import type { Group, Profile } from "@/lib/supabase/types";
import {
  DURATION_PRESETS_MIN,
  DateTimeFields,
  addMinutesToDateTimeParts,
  dateTimePartsToISOString,
  emptyDateTimeParts,
  type DateTimeParts,
} from "./date-time-fields";

function formatDurationLabel(minutes: number): string {
  if (minutes % 60 === 0) return `${minutes / 60} h`;
  return `${Math.floor(minutes / 60)} h ${minutes % 60}`;
}

export function CreateOutingDialog({
  friends,
  groups,
  defaultGroupId = "",
}: {
  friends: Profile[];
  groups: Group[];
  defaultGroupId?: string;
}) {
  const [open, setOpen] = useState(false);
  const [title, setTitle] = useState("");
  const [starts, setStarts] = useState<DateTimeParts>(emptyDateTimeParts);
  const [ends, setEnds] = useState<DateTimeParts>(emptyDateTimeParts);
  const [location, setLocation] = useState("");
  const [note, setNote] = useState("");
  const [friendIds, setFriendIds] = useState<string[]>([]);
  const [groupId, setGroupId] = useState(defaultGroupId);
  const [isPending, startTransition] = useTransition();
  const router = useRouter();

  function toggleFriend(id: string) {
    setFriendIds((ids) => ids.includes(id) ? ids.filter((friendId) => friendId !== id) : [...ids, id]);
  }

  function reset() {
    setTitle(""); setStarts(emptyDateTimeParts); setEnds(emptyDateTimeParts); setLocation(""); setNote(""); setFriendIds([]); setGroupId(defaultGroupId);
  }

  function submit(event: React.FormEvent) {
    event.preventDefault();
    startTransition(async () => {
      try {
        await createOuting({
          title,
          startsAt: dateTimePartsToISOString(starts),
          endsAt: dateTimePartsToISOString(ends),
          location,
          note,
          friendIds,
          groupId: groupId || undefined,
        });
        toast.success("Invitation envoyée");
        setOpen(false); reset(); router.refresh();
      } catch (error) {
        toast.error(error instanceof Error ? error.message : "Impossible d'envoyer l'invitation");
      }
    });
  }

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogTrigger render={<Button className="gap-2" />}><CalendarPlus className="size-4" />Créer une sortie</DialogTrigger>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-lg">
        <form onSubmit={submit}>
          <DialogHeader><DialogTitle>Nouvelle sortie</DialogTitle></DialogHeader>
          <p className="mt-1 text-sm text-muted-foreground">Choisis le créneau, puis les personnes à inviter.</p>
          <div className="space-y-4 py-5">
            <div className="space-y-1.5"><Label htmlFor="outing-title">Nom de la sortie</Label><Input id="outing-title" value={title} onChange={(e) => setTitle(e.target.value)} placeholder="Dîner chez Marco" autoFocus required /></div>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              <DateTimeFields legend="Début" idPrefix="outing-start" value={starts} onChange={setStarts} />
              <DateTimeFields legend="Fin" idPrefix="outing-end" value={ends} onChange={setEnds} />
            </div>
            {starts.date && starts.hour && starts.minute && (
              <div className="space-y-1.5">
                <Label>Durée rapide</Label>
                <div className="flex flex-wrap gap-1.5">
                  {DURATION_PRESETS_MIN.map((minutes) => (
                    <button
                      key={minutes}
                      type="button"
                      onClick={() => setEnds(addMinutesToDateTimeParts(starts, minutes))}
                      className="rounded-full border border-border px-3 py-1 text-xs text-muted-foreground transition-colors hover:border-primary/40 hover:bg-accent hover:text-foreground"
                    >
                      {formatDurationLabel(minutes)}
                    </button>
                  ))}
                </div>
              </div>
            )}
            <div className="space-y-1.5"><Label htmlFor="outing-location">Lieu <span className="font-normal text-muted-foreground">(facultatif)</span></Label><Input id="outing-location" value={location} onChange={(e) => setLocation(e.target.value)} placeholder="Canal Saint-Martin" /></div>
            <div className="space-y-1.5"><Label>Inviter un groupe <span className="font-normal text-muted-foreground">(facultatif)</span></Label><select value={groupId} onChange={(e) => setGroupId(e.target.value)} className="h-9 w-full rounded-md border border-input bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"><option value="">Aucun groupe</option>{groups.map((group) => <option key={group.id} value={group.id}>{group.name}</option>)}</select></div>
            {friends.length > 0 && <fieldset className="space-y-2"><legend className="text-sm font-medium">Inviter des amis</legend><div className="grid grid-cols-1 gap-1.5 sm:grid-cols-2">{friends.map((friend) => <label key={friend.id} className="flex cursor-pointer items-center gap-2 rounded-md border border-border px-3 py-2 text-sm hover:bg-muted"><input type="checkbox" checked={friendIds.includes(friend.id)} onChange={() => toggleFriend(friend.id)} className="accent-primary" />{friend.username}</label>)}</div></fieldset>}
            <div className="space-y-1.5"><Label htmlFor="outing-note">Note <span className="font-normal text-muted-foreground">(facultatif)</span></Label><Textarea id="outing-note" value={note} onChange={(e) => setNote(e.target.value)} placeholder="On réserve une table ?" /></div>
          </div>
          <DialogFooter><Button type="submit" disabled={isPending || !title.trim() || !starts.date || !starts.hour || !starts.minute || !ends.date || !ends.hour || !ends.minute || (friendIds.length === 0 && !groupId)}>{isPending ? "Envoi…" : "Envoyer l'invitation"}</Button></DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  );
}
