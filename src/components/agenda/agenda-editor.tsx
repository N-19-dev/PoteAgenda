"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter, usePathname, useSearchParams } from "next/navigation";
import { AnimatePresence, motion } from "framer-motion";
import { format } from "date-fns";
import { fr } from "date-fns/locale";
import { toast } from "sonner";
import { Clock, MapPin, Trash2, Users } from "lucide-react";
import { WeekGrid, type SlotSelection } from "@/components/calendar/week-grid";
import { MonthGrid } from "@/components/calendar/month-grid";
import { MiniCalendar } from "@/components/calendar/mini-calendar";
import { CalendarNav } from "@/components/calendar/calendar-nav";
import { Button } from "@/components/ui/button";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";
import {
  QUICK_LABELS,
  buildBusyGrid,
  colorForFriend,
  dateKey,
  eventSlotRangeForDay,
  getMonthStart,
  getWeekDates,
  getWeekStart,
  minutesToLabel,
  slotIndexToMinutes,
  slotRangeToTimes,
  type CalendarView,
} from "@/lib/schedule";
import { addCalendarEvent, deleteCalendarEvent } from "@/lib/actions/calendar-events";
import { createOuting } from "@/lib/actions/outings";
import type { BusyEvent, CalendarEvent, Outing, OutingResponse, Profile } from "@/lib/supabase/types";

type OutingWithResponse = Outing & { myResponse: OutingResponse };

export function AgendaEditor({
  view,
  anchorDate,
  events,
  friends,
  selectedFriendIds,
  friendsBusyEvents,
  outings,
  currentUserId,
}: {
  view: CalendarView;
  anchorDate: Date;
  events: CalendarEvent[];
  friends: Profile[];
  selectedFriendIds: string[];
  friendsBusyEvents: BusyEvent[];
  outings: OutingWithResponse[];
  currentUserId: string;
}) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [isPending, startTransition] = useTransition();

  const gridDates = useMemo(
    () => (view === "day" ? [anchorDate] : getWeekDates(getWeekStart(anchorDate))),
    [view, anchorDate],
  );

  const [createSelection, setCreateSelection] = useState<SlotSelection | null>(null);
  const [title, setTitle] = useState("");
  const [color, setColor] = useState<string>(QUICK_LABELS[0].color);
  const [inviteeIds, setInviteeIds] = useState<string[]>([]);
  const [location, setLocation] = useState("");
  const [note, setNote] = useState("");
  const [toDelete, setToDelete] = useState<CalendarEvent | null>(null);
  const [viewingOuting, setViewingOuting] = useState<OutingWithResponse | null>(null);

  function navigateTo(date: Date, viewOverride?: CalendarView) {
    const params = new URLSearchParams(searchParams.toString());
    params.set("date", dateKey(date));
    if (viewOverride) params.set("view", viewOverride);
    router.push(`${pathname}?${params.toString()}`, { scroll: false });
  }

  const selectedFriends = useMemo(
    () => friends.filter((f) => selectedFriendIds.includes(f.id)),
    [friends, selectedFriendIds],
  );

  const friendGrid = useMemo(
    () => buildBusyGrid(friendsBusyEvents, gridDates),
    [friendsBusyEvents, gridDates],
  );

  function toggleFriend(id: string) {
    const next = selectedFriendIds.includes(id)
      ? selectedFriendIds.filter((f) => f !== id)
      : [...selectedFriendIds, id];
    const params = new URLSearchParams(searchParams.toString());
    if (next.length > 0) {
      params.set("friends", next.join(","));
    } else {
      params.delete("friends");
    }
    startTransition(() => {
      router.push(`${pathname}?${params.toString()}`, { scroll: false });
    });
  }

  const blockByCell = useMemo(() => {
    const map = new Map<string, CalendarEvent>();
    for (const event of events) {
      const startAt = new Date(event.start_at);
      const endAt = new Date(event.end_at);
      gridDates.forEach((day, dayIndex) => {
        const range = eventSlotRangeForDay(startAt, endAt, day);
        if (!range) return;
        for (let s = range.startSlot; s < range.endSlot; s++) {
          map.set(`${dayIndex}-${s}`, event);
        }
      });
    }
    return map;
  }, [events, gridDates]);

  const outingByCell = useMemo(() => {
    const map = new Map<string, OutingWithResponse>();
    for (const outing of outings) {
      const startAt = new Date(outing.starts_at);
      const endAt = new Date(outing.ends_at);
      gridDates.forEach((day, dayIndex) => {
        const range = eventSlotRangeForDay(startAt, endAt, day);
        if (!range) return;
        for (let slot = range.startSlot; slot < range.endSlot; slot++) map.set(`${dayIndex}-${slot}`, outing);
      });
    }
    return map;
  }, [outings, gridDates]);

  function isSlotStart(timestamp: string, day: number, slot: number) {
    const startAt = new Date(timestamp);
    return startAt.toDateString() === gridDates[day].toDateString()
      && startAt.getHours() * 60 + startAt.getMinutes() === slotIndexToMinutes(slot);
  }

  function handleRangeSelect(selection: SlotSelection) {
    if (selection.endSlot - selection.startSlot === 1) {
      const existingOuting = outingByCell.get(`${selection.day}-${selection.startSlot}`);
      if (existingOuting) {
        setViewingOuting(existingOuting);
        return;
      }
      const existing = blockByCell.get(`${selection.day}-${selection.startSlot}`);
      if (existing) {
        setToDelete(existing);
        return;
      }
    }
    setTitle("");
    setColor(QUICK_LABELS[0].color);
    setInviteeIds(selectedFriendIds);
    setLocation("");
    setNote("");
    setCreateSelection(selection);
  }

  function toggleInvitee(id: string) {
    setInviteeIds((ids) => (ids.includes(id) ? ids.filter((i) => i !== id) : [...ids, id]));
  }

  function handleCreate() {
    if (!createSelection) return;
    const date = gridDates[createSelection.day];
    const { start_at, end_at } = slotRangeToTimes(
      date,
      createSelection.startSlot,
      createSelection.endSlot,
    );
    const isOuting = inviteeIds.length > 0;
    startTransition(async () => {
      try {
        if (isOuting) {
          await createOuting({
            title: title.trim() || "Créneau",
            startsAt: start_at,
            endsAt: end_at,
            location,
            note,
            friendIds: inviteeIds,
          });
          toast.success("Invitation envoyée");
        } else {
          await addCalendarEvent({
            title: title.trim() || "Occupé",
            start_at,
            end_at,
            color,
          });
          toast.success("Créneau ajouté");
        }
        setCreateSelection(null);
        router.refresh();
      } catch (error) {
        toast.error(
          error instanceof Error && isOuting ? error.message : "Impossible d'ajouter ce créneau",
        );
      }
    });
  }

  function handleDelete() {
    if (!toDelete) return;
    startTransition(async () => {
      try {
        await deleteCalendarEvent(toDelete.id);
        toast.success("Créneau supprimé");
        setToDelete(null);
        router.refresh();
      } catch {
        toast.error("Suppression impossible");
      }
    });
  }

  return (
    <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:gap-4">
      <aside className="hidden w-56 shrink-0 lg:block">
        <div className="sticky top-20 space-y-3">
          <MiniCalendar selected={anchorDate} onSelect={(d) => navigateTo(d)} />
        </div>
      </aside>

      <div className="min-w-0 flex-1 space-y-3">
        <CalendarNav view={view} date={anchorDate} />

        {friends.length > 0 && view !== "month" && (
          <div className="rounded-xl border border-border bg-card p-3">
            <div className="mb-2 flex items-center gap-1.5 text-xs font-medium text-muted-foreground">
              <Users className="h-3.5 w-3.5" />
              Voir la dispo de mes amis directement sur mon calendrier
            </div>
            <div className="flex flex-wrap gap-1.5">
              {friends.map((f) => {
                const active = selectedFriendIds.includes(f.id);
                const dot = colorForFriend(f.id);
                return (
                  <button
                      key={f.id}
                      type="button"
                      onClick={() => toggleFriend(f.id)}
                      disabled={isPending}
                      className={cn(
                        "flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs transition-colors",
                        active
                          ? "border-primary/40 bg-accent text-foreground"
                          : "border-border/60 text-muted-foreground hover:bg-muted hover:text-foreground",
                      )}
                    >
                      <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: dot }} />
                      <Avatar className="h-4 w-4">
                        <AvatarFallback className="text-[8px]">
                          {f.username.slice(0, 2).toUpperCase()}
                        </AvatarFallback>
                      </Avatar>
                      @{f.username}
                    </button>
                );
              })}
            </div>
          </div>
        )}

        {view === "month" ? (
          <MonthGrid
            monthStart={getMonthStart(anchorDate)}
            events={events}
            outings={outings}
            onSelectDay={(d) => navigateTo(d, "day")}
          />
        ) : (
          <div className="space-y-2">
            <p className="text-[11px] text-muted-foreground">
              Touche un créneau libre pour ajouter une indisponibilité, ou proposer une sortie à un ami sélectionné ci-dessus.
              {selectedFriends.length > 0 && " Les points colorés montrent quand tes amis sont occupés."}
            </p>

            <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5 text-[11px] text-muted-foreground">
              <span className="flex items-center gap-1.5">
                <span className="h-2.5 w-2.5 rounded-sm border border-border/60 bg-transparent" />
                Libre
              </span>
              <span className="flex items-center gap-1.5">
                <span className="h-2.5 w-2.5 rounded-sm" style={{ backgroundColor: `${QUICK_LABELS[0].color}55` }} />
                Occupé (indisponibilité)
              </span>
              <span className="flex items-center gap-1.5">
                <span className="h-2.5 w-2.5 rounded-sm bg-primary/20" />
                Sortie confirmée
              </span>
              <span className="flex items-center gap-1.5">
                <span className="h-2.5 w-2.5 rounded-sm border border-dashed border-amber-400/70 bg-amber-400/10" />
                Invitation en attente
              </span>
              {selectedFriends.length > 0 && (
                <span className="flex items-center gap-1.5">
                  <span className="h-2 w-2 rounded-full ring-2 ring-background" style={{ backgroundColor: colorForFriend(selectedFriends[0].id) }} />
                  Ami occupé
                </span>
              )}
            </div>

            <AnimatePresence mode="wait">
              <motion.div
                key={`${view}-${dateKey(anchorDate)}`}
                initial={{ opacity: 0, y: 6 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -6 }}
                transition={{ duration: 0.16, ease: "easeOut" }}
              >
                <WeekGrid
                  weekDates={gridDates}
                  interactive
                  onRangeSelect={handleRangeSelect}
                  cellClassName={(day, slot) => {
                    const block = blockByCell.get(`${day}-${slot}`);
                    const outing = outingByCell.get(`${day}-${slot}`);
                    return block || outing ? "" : "bg-transparent";
                  }}
                  cellContent={(day, slot) => {
                    const block = blockByCell.get(`${day}-${slot}`);
                    const outing = outingByCell.get(`${day}-${slot}`);
                    const busyFriendIds = friendGrid.busyMembers[day]?.[slot] ?? [];
                    return (
                      <div className="relative h-full w-full">
                        {block && (
                          <div
                            className="absolute inset-0"
                            style={{ backgroundColor: `${block.color}55` }}
                            title={block.title}
                          >
                            {isSlotStart(block.start_at, day, slot) && (
                              <span className="block truncate px-1 pt-0.5 text-[10px] font-medium text-foreground">
                                {block.title}
                              </span>
                            )}
                          </div>
                        )}
                        {outing && (() => {
                          const isPendingInvite = outing.myResponse === "pending" && outing.creator_id !== currentUserId;
                          return (
                            <div
                              className={cn(
                                "absolute inset-0",
                                isPendingInvite
                                  ? "border border-dashed border-amber-400/70 bg-amber-400/10"
                                  : "bg-primary/20",
                              )}
                              title={outing.title}
                            >
                              {isSlotStart(outing.starts_at, day, slot) && (
                                <span
                                  className={cn(
                                    "flex items-center gap-0.5 truncate px-1 pt-0.5 text-[10px] font-semibold",
                                    isPendingInvite ? "text-amber-600 dark:text-amber-400" : "text-primary",
                                  )}
                                >
                                  {isPendingInvite ? <Clock className="h-2.5 w-2.5 shrink-0" /> : <Users className="h-2.5 w-2.5 shrink-0" />}
                                  <span className="truncate">{outing.title}</span>
                                </span>
                              )}
                            </div>
                          );
                        })()}
                        {busyFriendIds.length > 0 && (
                          <div className="absolute inset-x-0.5 bottom-0.5 flex justify-center gap-1">
                            {busyFriendIds.slice(0, 4).map((id) => (
                              <span
                                key={id}
                                className="h-2 w-2 rounded-full ring-2 ring-background"
                                style={{ backgroundColor: colorForFriend(id) }}
                              />
                            ))}
                          </div>
                        )}
                      </div>
                    );
                  }}
                />
              </motion.div>
            </AnimatePresence>
          </div>
        )}
      </div>

      {/* Dialog création */}
      <Dialog open={!!createSelection} onOpenChange={(open) => !open && setCreateSelection(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {createSelection && (
                <>
                  {format(gridDates[createSelection.day], "EEEE d MMMM", { locale: fr })} ·{" "}
                  <span className="tabular-nums">
                    {minutesToLabel(slotIndexToMinutes(createSelection.startSlot))} –{" "}
                    {minutesToLabel(slotIndexToMinutes(createSelection.endSlot))}
                  </span>
                </>
              )}
            </DialogTitle>
          </DialogHeader>

          <div className="space-y-4">
            {friends.length > 0 && (
              <div className="space-y-1.5">
                <Label>Inviter des amis à ce créneau <span className="font-normal text-muted-foreground">(facultatif)</span></Label>
                <div className="flex flex-wrap gap-1.5">
                  {friends.map((f) => {
                    const active = inviteeIds.includes(f.id);
                    return (
                      <button
                        key={f.id}
                        type="button"
                        onClick={() => toggleInvitee(f.id)}
                        className={cn(
                          "flex items-center gap-1.5 rounded-full border px-2.5 py-1 text-xs transition-colors",
                          active
                            ? "border-primary/40 bg-accent text-foreground"
                            : "border-border/60 text-muted-foreground hover:bg-muted hover:text-foreground",
                        )}
                      >
                        <span className="h-2 w-2 shrink-0 rounded-full" style={{ backgroundColor: colorForFriend(f.id) }} />
                        @{f.username}
                      </button>
                    );
                  })}
                </div>
              </div>
            )}

            {inviteeIds.length === 0 && (
              <div className="flex flex-wrap gap-1.5">
                {QUICK_LABELS.map((q) => (
                  <button
                    key={q.label}
                    type="button"
                    onClick={() => {
                      setTitle(q.label);
                      setColor(q.color);
                    }}
                    className={cn(
                      "rounded-full border px-3 py-1 text-xs transition-colors",
                      title === q.label ? "border-transparent text-white" : "border-border",
                    )}
                    style={title === q.label ? { backgroundColor: q.color } : undefined}
                  >
                    {q.label}
                  </button>
                ))}
              </div>
            )}

            <div className="space-y-1.5">
              <Label htmlFor="event-title">
                {inviteeIds.length > 0 ? "Nom de la sortie" : "Titre (visible par toi uniquement)"}
              </Label>
              <Input
                id="event-title"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                placeholder={inviteeIds.length > 0 ? "Dîner chez Marco" : "Occupé"}
              />
            </div>

            {inviteeIds.length > 0 && (
              <>
                <div className="space-y-1.5">
                  <Label htmlFor="event-location">Lieu <span className="font-normal text-muted-foreground">(facultatif)</span></Label>
                  <Input
                    id="event-location"
                    value={location}
                    onChange={(e) => setLocation(e.target.value)}
                    placeholder="Canal Saint-Martin"
                  />
                </div>
                <div className="space-y-1.5">
                  <Label htmlFor="event-note">Note <span className="font-normal text-muted-foreground">(facultatif)</span></Label>
                  <Textarea
                    id="event-note"
                    value={note}
                    onChange={(e) => setNote(e.target.value)}
                    placeholder="On réserve une table ?"
                  />
                </div>
              </>
            )}
          </div>

          <DialogFooter>
            <Button onClick={handleCreate} disabled={isPending || (inviteeIds.length > 0 && !title.trim())}>
              {isPending
                ? "Envoi..."
                : inviteeIds.length > 0
                  ? "Envoyer l'invitation"
                  : "Ajouter"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Dialog suppression */}
      <Dialog open={!!toDelete} onOpenChange={(open) => !open && setToDelete(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{toDelete?.title}</DialogTitle>
          </DialogHeader>
          {toDelete && (
            <p className="text-sm text-muted-foreground">
              {format(new Date(toDelete.start_at), "EEEE d MMMM", { locale: fr })} ·{" "}
              {format(new Date(toDelete.start_at), "HH:mm")} –{" "}
              {format(new Date(toDelete.end_at), "HH:mm")}
            </p>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setToDelete(null)}>
              Annuler
            </Button>
            <Button variant="destructive" disabled={isPending} onClick={handleDelete} className="gap-1.5">
              <Trash2 className="h-4 w-4" />
              Supprimer
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Dialog détail sortie */}
      <Dialog open={!!viewingOuting} onOpenChange={(open) => !open && setViewingOuting(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>{viewingOuting?.title}</DialogTitle>
          </DialogHeader>
          {viewingOuting && (
            <div className="space-y-1.5 text-sm text-muted-foreground">
              {viewingOuting.myResponse === "pending" && viewingOuting.creator_id !== currentUserId ? (
                <p className="flex items-center gap-1.5 text-xs font-medium text-amber-600 dark:text-amber-400">
                  <Clock className="size-3.5" />
                  Invitation en attente de ta réponse
                </p>
              ) : (
                <p className="flex items-center gap-1.5 text-xs font-medium text-primary">
                  <Users className="size-3.5" />
                  Sortie confirmée
                </p>
              )}
              <p>
                {format(new Date(viewingOuting.starts_at), "EEEE d MMMM", { locale: fr })} ·{" "}
                {format(new Date(viewingOuting.starts_at), "HH:mm")} –{" "}
                {format(new Date(viewingOuting.ends_at), "HH:mm")}
              </p>
              {viewingOuting.location && (
                <p className="flex items-center gap-1">
                  <MapPin className="size-3.5" />
                  {viewingOuting.location}
                </p>
              )}
              {viewingOuting.note && <p className="text-foreground">{viewingOuting.note}</p>}
            </div>
          )}
          <DialogFooter>
            <Button variant="outline" onClick={() => setViewingOuting(null)}>
              Fermer
            </Button>
            <Button onClick={() => router.push("/invitations")}>Gérer l&apos;invitation</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
