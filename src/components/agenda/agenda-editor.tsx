"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter, usePathname, useSearchParams } from "next/navigation";
import { AnimatePresence, motion } from "framer-motion";
import { format } from "date-fns";
import { fr } from "date-fns/locale";
import { toast } from "sonner";
import { Check, Clock, MapPin, Minus, Plus, Trash2, Users } from "lucide-react";
import { ROW_HEIGHT, WeekGrid, type SlotSelection } from "@/components/calendar/week-grid";
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
  SLOT_MINUTES,
  SLOTS_PER_DAY,
  buildBusyGrid,
  chipForegroundColor,
  colorForFriend,
  dateKey,
  eventSlotRangeForDay,
  getMonthStart,
  getWeekDates,
  getWeekStart,
  minutesToLabel,
  slotIndexToMinutes,
  slotRangeToTimes,
  titleForBusySlot,
  type CalendarView,
} from "@/lib/schedule";
import { addCalendarEvent, deleteCalendarEvent } from "@/lib/actions/calendar-events";
import { createOuting, respondToOuting, setOutingConfirmed } from "@/lib/actions/outings";
import type { BusyEvent, CalendarEvent, Outing, OutingResponse, Profile } from "@/lib/supabase/types";

type OutingWithResponse = Outing & { myResponse: OutingResponse; isConfirmed: boolean };

function formatDuration(totalMinutes: number): string {
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (minutes === 0) return `${hours} h`;
  if (hours === 0) return `${minutes} min`;
  return `${hours} h ${minutes}`;
}

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

  function eventSpanHeight(startIso: string, endIso: string) {
    const durationMin = (new Date(endIso).getTime() - new Date(startIso).getTime()) / 60_000;
    return Math.max(ROW_HEIGHT, (durationMin / SLOT_MINUTES) * ROW_HEIGHT - 2);
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

  function adjustDuration(deltaSlots: number) {
    setCreateSelection((selection) => {
      if (!selection) return selection;
      const endSlot = Math.min(
        SLOTS_PER_DAY,
        Math.max(selection.startSlot + 1, selection.endSlot + deltaSlots),
      );
      return { ...selection, endSlot };
    });
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

  function handleConfirmOuting() {
    if (!viewingOuting) return;
    startTransition(async () => {
      try {
        await setOutingConfirmed(viewingOuting.id, true);
        toast.success("Sortie confirmée");
        setViewingOuting(null);
        router.refresh();
      } catch {
        toast.error("Impossible de confirmer la sortie");
      }
    });
  }

  function handleAcceptOuting() {
    if (!viewingOuting) return;
    startTransition(async () => {
      try {
        await respondToOuting(viewingOuting.id, "accepted");
        toast.success("Tu viens à cette sortie");
        setViewingOuting(null);
        router.refresh();
      } catch {
        toast.error("Impossible de valider ta réponse");
      }
    });
  }

  return (
    <div className="flex flex-col gap-3 lg:flex-row lg:items-start lg:gap-4">
      <aside className="hidden w-56 shrink-0 lg:block lg:border-r lg:border-border/50 lg:pr-4">
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
              {selectedFriends.length > 0 && " Les hachures grises montrent quand tes amis sont occupés."}
            </p>

            <div className="flex flex-wrap items-center gap-x-4 gap-y-1.5 text-[11px] text-muted-foreground">
              <span className="flex items-center gap-1.5">
                <span className="h-2.5 w-2.5 shrink-0 rounded-full border border-border/60 bg-transparent" />
                Libre
              </span>
              <span className="flex items-center gap-1.5">
                <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ backgroundColor: QUICK_LABELS[0].color }} />
                Occupé (indisponibilité)
              </span>
              <span className="flex items-center gap-1.5">
                <span className="h-2.5 w-2.5 shrink-0 rounded-full bg-emerald-500" />
                Sortie confirmée
              </span>
              <span className="flex items-center gap-1.5">
                <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ backgroundColor: "#f59e0b" }} />
                Invitation en attente de ta réponse
              </span>
              <span className="flex items-center gap-1.5">
                <span className="h-2.5 w-2.5 shrink-0 rounded-full" style={{ backgroundColor: "var(--muted-foreground)" }} />
                En attente d&apos;autres invités
              </span>
              {selectedFriends.length > 0 && (
                <span className="flex items-center gap-1.5">
                  <span className="relative h-2.5 w-2.5 shrink-0 rounded-sm bg-busy-other">
                    <span className="absolute left-0 top-1/2 h-px w-full -rotate-45 bg-busy-other-foreground" />
                  </span>
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
                    return block || outing ? "border-t-transparent" : "bg-transparent";
                  }}
                  cellContent={(day, slot) => {
                    const block = blockByCell.get(`${day}-${slot}`);
                    const outing = outingByCell.get(`${day}-${slot}`);
                    const busyFriendIds = friendGrid.busyMembers[day]?.[slot] ?? [];
                    return (
                      <div className="relative h-full w-full">
                        {block && isSlotStart(block.start_at, day, slot) && (() => {
                          const height = eventSpanHeight(block.start_at, block.end_at);
                          const showTime = height >= ROW_HEIGHT * 2 - 2;
                          const blockColor = block.title.trim().toLowerCase() === "occupé" ? "#ef4444" : block.color;
                          return (
                            <div
                              className="absolute inset-x-0 top-0 z-10 overflow-hidden rounded-md border-l-[3px] px-1.5 py-0.5"
                              style={{ height, backgroundColor: `${blockColor}1f`, borderColor: blockColor }}
                              title={`${block.title} · ${format(new Date(block.start_at), "HH:mm")}–${format(new Date(block.end_at), "HH:mm")}`}
                            >
                              <span className="block truncate text-[10px] font-semibold leading-tight" style={{ color: blockColor }}>
                                {block.title}
                              </span>
                              {showTime && (
                                <span className="mt-0.5 flex items-center gap-0.5 truncate text-[9px] opacity-80" style={{ color: blockColor }}>
                                  <Clock className="h-2 w-2 shrink-0" />
                                  {format(new Date(block.start_at), "HH:mm")}–{format(new Date(block.end_at), "HH:mm")}
                                </span>
                              )}
                            </div>
                          );
                        })()}
                        {outing && isSlotStart(outing.starts_at, day, slot) && (() => {
                          const needsMyResponse = outing.myResponse === "pending" && outing.creator_id !== currentUserId;
                          const awaitingOthers = !needsMyResponse && !outing.isConfirmed;
                          const height = eventSpanHeight(outing.starts_at, outing.ends_at);
                          const showTime = height >= ROW_HEIGHT * 2 - 2;
                          return (
                            <div
                              className={cn(
                                "absolute inset-x-0 top-0 z-10 overflow-hidden rounded-md border-l-[3px] px-1.5 py-0.5",
                                needsMyResponse
                                  ? "border-l-amber-500 bg-amber-400/10"
                                  : awaitingOthers
                                    ? "border-l-muted-foreground bg-muted"
                                    : "border-l-emerald-500 bg-emerald-500/10",
                              )}
                              style={{ height }}
                              title={`${outing.title} · ${format(new Date(outing.starts_at), "HH:mm")}–${format(new Date(outing.ends_at), "HH:mm")}`}
                            >
                              <span
                                className={cn(
                                  "flex items-center gap-0.5 truncate text-[10px] font-semibold leading-tight",
                                  needsMyResponse
                                    ? "text-amber-600 dark:text-amber-400"
                                    : awaitingOthers
                                      ? "text-muted-foreground"
                                      : "text-emerald-600",
                                )}
                              >
                                {needsMyResponse ? (
                                  <Clock className="h-2.5 w-2.5 shrink-0" />
                                ) : (
                                  <Users className="h-2.5 w-2.5 shrink-0" />
                                )}
                                <span className="truncate">{outing.title}</span>
                              </span>
                              {showTime && (
                                <span
                                  className={cn(
                                    "mt-0.5 flex items-center gap-0.5 truncate text-[9px] opacity-80",
                                    needsMyResponse
                                      ? "text-amber-600 dark:text-amber-400"
                                      : awaitingOthers
                                        ? "text-muted-foreground"
                                        : "text-emerald-600",
                                  )}
                                >
                                  <Clock className="h-2 w-2 shrink-0" />
                                  {format(new Date(outing.starts_at), "HH:mm")}–{format(new Date(outing.ends_at), "HH:mm")}
                                </span>
                              )}
                            </div>
                          );
                        })()}
                        {busyFriendIds.length > 0 && (() => {
                          const tooltip = busyFriendIds
                            .slice(0, 4)
                            .map((id) => {
                              const sharedTitle = titleForBusySlot(friendsBusyEvents, id, gridDates[day], slot);
                              const username = friends.find((f) => f.id === id)?.username;
                              return sharedTitle
                                ? `${username ? `@${username} : ` : ""}${sharedTitle}`
                                : username
                                  ? `@${username} occupé·e`
                                  : undefined;
                            })
                            .filter(Boolean)
                            .join(" · ");
                          return (
                            <div
                              className="absolute inset-x-0.5 inset-y-0.5 z-20 rounded-sm border border-busy-other-foreground/20 bg-busy-other/80"
                              style={{
                                backgroundImage:
                                  "repeating-linear-gradient(135deg, transparent 0 5px, color-mix(in oklch, var(--busy-other-foreground) 26%, transparent) 5px 7px)",
                              }}
                              title={tooltip || undefined}
                            >
                              <span className="sr-only">
                                {busyFriendIds.length} ami{busyFriendIds.length > 1 ? "s" : ""} occupé{busyFriendIds.length > 1 ? "s" : ""}
                              </span>
                            </div>
                          );
                        })()}
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
            {createSelection && (
              <div className="flex items-center justify-between gap-2 rounded-md border border-border/60 bg-muted/30 px-3 py-2">
                <span className="text-xs text-muted-foreground">
                  Durée : {formatDuration((createSelection.endSlot - createSelection.startSlot) * 30)}
                </span>
                <div className="flex items-center gap-1.5">
                  <Button
                    type="button"
                    size="icon"
                    variant="outline"
                    className="h-7 w-7"
                    onClick={() => adjustDuration(-1)}
                    disabled={createSelection.endSlot - createSelection.startSlot <= 1}
                    aria-label="Réduire de 30 minutes"
                  >
                    <Minus className="h-3.5 w-3.5" />
                  </Button>
                  <Button
                    type="button"
                    size="icon"
                    variant="outline"
                    className="h-7 w-7"
                    onClick={() => adjustDuration(1)}
                    disabled={createSelection.endSlot >= SLOTS_PER_DAY}
                    aria-label="Prolonger de 30 minutes"
                  >
                    <Plus className="h-3.5 w-3.5" />
                  </Button>
                </div>
              </div>
            )}
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
                      title === q.label ? "border-transparent" : "border-border",
                    )}
                    style={
                      title === q.label
                        ? { backgroundColor: q.color, color: chipForegroundColor(q.color) }
                        : undefined
                    }
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
              ) : !viewingOuting.isConfirmed ? (
                <p className="flex items-center gap-1.5 text-xs font-medium text-muted-foreground">
                  <Users className="size-3.5" />
                  En attente de la réponse d&apos;autres invités
                </p>
              ) : (
                <p className="flex items-center gap-1.5 text-xs font-medium text-emerald-600">
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
            {viewingOuting?.myResponse === "pending" && viewingOuting.creator_id !== currentUserId && (
              <Button disabled={isPending} onClick={handleAcceptOuting} className="gap-1.5">
                <Check className="h-4 w-4" />
                Valider ma présence
              </Button>
            )}
            {viewingOuting && !viewingOuting.isConfirmed && viewingOuting.creator_id === currentUserId && (
              <Button variant="outline" disabled={isPending} onClick={handleConfirmOuting} className="gap-1.5">
                <Users className="h-4 w-4" />
                Confirmer la sortie
              </Button>
            )}
            <Button onClick={() => router.push("/invitations")}>Gérer l&apos;invitation</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
