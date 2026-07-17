"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { format } from "date-fns";
import { fr } from "date-fns/locale";
import { toast } from "sonner";
import { Trash2 } from "lucide-react";
import { WeekGrid, type SlotSelection } from "@/components/calendar/week-grid";
import { WeekNav } from "@/components/calendar/week-nav";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";
import {
  QUICK_LABELS,
  eventSlotRangeForDay,
  getWeekDates,
  minutesToLabel,
  slotIndexToMinutes,
  slotRangeToTimes,
} from "@/lib/schedule";
import { addCalendarEvent, deleteCalendarEvent } from "@/lib/actions/calendar-events";
import type { CalendarEvent } from "@/lib/supabase/types";

export function AgendaEditor({
  weekStart,
  events,
}: {
  weekStart: Date;
  events: CalendarEvent[];
}) {
  const router = useRouter();
  const [isPending, startTransition] = useTransition();

  const weekDates = useMemo(() => getWeekDates(weekStart), [weekStart]);

  const [createSelection, setCreateSelection] = useState<SlotSelection | null>(null);
  const [title, setTitle] = useState("");
  const [color, setColor] = useState<string>(QUICK_LABELS[0].color);
  const [toDelete, setToDelete] = useState<CalendarEvent | null>(null);

  const blockByCell = useMemo(() => {
    const map = new Map<string, CalendarEvent>();
    for (const event of events) {
      const startAt = new Date(event.start_at);
      const endAt = new Date(event.end_at);
      weekDates.forEach((day, dayIndex) => {
        const range = eventSlotRangeForDay(startAt, endAt, day);
        if (!range) return;
        for (let s = range.startSlot; s < range.endSlot; s++) {
          map.set(`${dayIndex}-${s}`, event);
        }
      });
    }
    return map;
  }, [events, weekDates]);

  function handleRangeSelect(selection: SlotSelection) {
    if (selection.endSlot - selection.startSlot === 1) {
      const existing = blockByCell.get(`${selection.day}-${selection.startSlot}`);
      if (existing) {
        setToDelete(existing);
        return;
      }
    }
    setTitle("");
    setColor(QUICK_LABELS[0].color);
    setCreateSelection(selection);
  }

  function handleCreate() {
    if (!createSelection) return;
    const date = weekDates[createSelection.day];
    const { start_at, end_at } = slotRangeToTimes(
      date,
      createSelection.startSlot,
      createSelection.endSlot,
    );
    startTransition(async () => {
      try {
        await addCalendarEvent({
          title: title.trim() || "Occupé",
          start_at,
          end_at,
          color,
        });
        toast.success("Créneau ajouté");
        setCreateSelection(null);
        router.refresh();
      } catch {
        toast.error("Impossible d'ajouter ce créneau");
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
    <div className="space-y-3">
      <WeekNav weekStart={weekStart} />

      <p className="text-[11px] text-muted-foreground">
        Glisse sur la grille pour ajouter une indisponibilité. Touche un créneau existant pour le
        supprimer.
      </p>

      <WeekGrid
        weekDates={weekDates}
        interactive
        onRangeSelect={handleRangeSelect}
        cellClassName={(day, slot) => {
          const block = blockByCell.get(`${day}-${slot}`);
          return block ? "" : "bg-transparent hover:bg-accent/40";
        }}
        cellContent={(day, slot) => {
          const block = blockByCell.get(`${day}-${slot}`);
          if (!block) return null;
          return <div className="h-full w-full" style={{ backgroundColor: `${block.color}55` }} />;
        }}
      />

      {/* Dialog création */}
      <Dialog open={!!createSelection} onOpenChange={(open) => !open && setCreateSelection(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>
              {createSelection && (
                <>
                  {format(weekDates[createSelection.day], "EEEE d MMMM", { locale: fr })} ·{" "}
                  {minutesToLabel(slotIndexToMinutes(createSelection.startSlot))} –{" "}
                  {minutesToLabel(slotIndexToMinutes(createSelection.endSlot))}
                </>
              )}
            </DialogTitle>
          </DialogHeader>

          <div className="space-y-4">
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

            <div className="space-y-1.5">
              <Label htmlFor="event-title">Titre (visible par toi uniquement)</Label>
              <Input
                id="event-title"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                placeholder="Occupé"
              />
            </div>
          </div>

          <DialogFooter>
            <Button onClick={handleCreate} disabled={isPending}>
              {isPending ? "Ajout..." : "Ajouter"}
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
    </div>
  );
}
