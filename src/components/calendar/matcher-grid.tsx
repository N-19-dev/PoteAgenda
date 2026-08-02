"use client";

import { useMemo, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { format } from "date-fns";
import { fr } from "date-fns/locale";
import { toast } from "sonner";
import { WeekGrid } from "@/components/calendar/week-grid";
import { WeekNav } from "@/components/calendar/week-nav";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { cn } from "@/lib/utils";
import { SLOTS_PER_DAY, buildBusyGrid, getWeekDates, minutesToLabel, slotIndexToMinutes, slotRangeToTimes, slotStatus } from "@/lib/schedule";
import { createOuting } from "@/lib/actions/outings";
import type { BusyEvent, Profile } from "@/lib/supabase/types";
import { CalendarPlus, Check, X } from "lucide-react";

interface MatcherGridProps {
  weekStart: Date;
  groupId: string;
  members: Profile[];
  busyEvents: BusyEvent[];
}

const DURATION_PRESETS_SLOTS = [1, 2, 3, 4];

export function MatcherGrid({ weekStart, groupId, members, busyEvents }: MatcherGridProps) {
  const [selected, setSelected] = useState<{ day: number; slot: number } | null>(null);
  const [creatingOuting, setCreatingOuting] = useState(false);
  const [outingTitle, setOutingTitle] = useState("");
  const [durationSlots, setDurationSlots] = useState(1);
  const [isPending, startTransition] = useTransition();
  const router = useRouter();

  const weekDates = useMemo(() => getWeekDates(weekStart), [weekStart]);
  const grid = useMemo(() => buildBusyGrid(busyEvents, weekDates), [busyEvents, weekDates]);

  const status = (day: number, slot: number) =>
    slotStatus(grid.busyCounts[day][slot], members.length);

  const cellClassName = (day: number, slot: number) => {
    const s = status(day, slot);
    if (s === "free-all") return "bg-emerald-500/20 hover:bg-emerald-500/30";
    if (s === "busy-all") return "bg-busy-other hover:bg-busy-other";
    return "bg-amber-400/15 hover:bg-amber-400/25";
  };

  const selectedInfo =
    selected &&
    (() => {
      const busyIds = new Set(grid.busyMembers[selected.day][selected.slot]);
      return {
        date: weekDates[selected.day],
        minutes: slotIndexToMinutes(selected.slot),
        members: members.map((m) => ({ ...m, busy: busyIds.has(m.id) })),
      };
    })();

  function closeDialog() {
    setSelected(null);
    setCreatingOuting(false);
    setOutingTitle("");
    setDurationSlots(1);
  }

  function submitOuting() {
    if (!selected) return;
    const { start_at, end_at } = slotRangeToTimes(
      weekDates[selected.day],
      selected.slot,
      Math.min(SLOTS_PER_DAY, selected.slot + durationSlots),
    );
    startTransition(async () => {
      try {
        await createOuting({
          title: outingTitle.trim() || "Sortie",
          startsAt: start_at,
          endsAt: end_at,
          friendIds: [],
          groupId,
        });
        toast.success("Invitation envoyée à tout le groupe");
        closeDialog();
        router.refresh();
      } catch (error) {
        toast.error(error instanceof Error ? error.message : "Impossible de créer la sortie");
      }
    });
  }

  return (
    <div className="space-y-3">
      <WeekNav weekStart={weekStart} />

      <div className="glass-panel flex flex-wrap items-center gap-3 rounded-xl px-3 py-2 text-xs text-muted-foreground">
        <span className="flex items-center gap-1.5">
          <span className="h-3 w-3 rounded-sm bg-emerald-500/50" />
          Tout le monde est libre
        </span>
        <span className="flex items-center gap-1.5">
          <span className="h-3 w-3 rounded-sm bg-amber-400/40" />
          Certains sont occupés
        </span>
        <span className="flex items-center gap-1.5">
          <span className="h-3 w-3 rounded-sm bg-busy-other" />
          Personne n&apos;est libre
        </span>
        <span className="text-[11px]">Touche un créneau pour voir qui est dispo</span>
      </div>

      <WeekGrid
        weekDates={weekDates}
        cellClassName={cellClassName}
        onCellTap={(day, slot) => setSelected({ day, slot })}
      />

      <Dialog
        open={!!selected}
        onOpenChange={(open) => {
          if (!open) closeDialog();
        }}
      >
        <DialogContent>
          {selectedInfo && !creatingOuting && (
            <>
              <DialogHeader>
                <DialogTitle>
                  {format(selectedInfo.date, "EEEE d MMMM", { locale: fr })} ·{" "}
                  <span className="tabular-nums">{minutesToLabel(selectedInfo.minutes)}</span>
                </DialogTitle>
              </DialogHeader>
              <ul className="space-y-1.5">
                {selectedInfo.members.map((m) => (
                  <li key={m.id} className="flex items-center gap-2 text-sm">
                    <Avatar className="h-6 w-6">
                      <AvatarFallback className="text-[10px]">
                        {m.username.slice(0, 2).toUpperCase()}
                      </AvatarFallback>
                    </Avatar>
                    <span className={cn("flex-1 truncate", m.busy && "text-muted-foreground")}>
                      {m.username}
                    </span>
                    {m.busy ? (
                      <span className="flex items-center gap-1 font-mono text-[10px] uppercase tracking-wide text-muted-foreground">
                        <X className="h-3.5 w-3.5" /> Occupé
                      </span>
                    ) : (
                      <span className="flex items-center gap-1 font-mono text-[10px] uppercase tracking-wide text-emerald-500">
                        <Check className="h-3.5 w-3.5" /> Libre
                      </span>
                    )}
                  </li>
                ))}
              </ul>
              {status(selected!.day, selected!.slot) === "free-all" && (
                <Button className="mt-4 gap-1.5" size="sm" onClick={() => setCreatingOuting(true)}>
                  <CalendarPlus className="size-4" />
                  Créer une sortie sur ce créneau
                </Button>
              )}
            </>
          )}
          {selectedInfo && creatingOuting && (
            <>
              <DialogHeader>
                <DialogTitle>
                  Sortie · {format(selectedInfo.date, "EEEE d MMMM", { locale: fr })}
                </DialogTitle>
              </DialogHeader>
              <div className="space-y-4 py-2">
                <div className="space-y-1.5">
                  <Label htmlFor="matcher-outing-title">Nom de la sortie</Label>
                  <Input
                    id="matcher-outing-title"
                    value={outingTitle}
                    onChange={(e) => setOutingTitle(e.target.value)}
                    placeholder="Dîner chez Marco"
                    autoFocus
                  />
                </div>
                <div className="space-y-1.5">
                  <Label>Durée</Label>
                  <div className="flex flex-wrap gap-1.5">
                    {DURATION_PRESETS_SLOTS.map((slots) => (
                      <button
                        key={slots}
                        type="button"
                        onClick={() => setDurationSlots(slots)}
                        className={cn(
                          "rounded-full border px-3 py-1 text-xs transition-colors",
                          durationSlots === slots
                            ? "border-primary/40 bg-accent text-foreground"
                            : "border-border text-muted-foreground hover:bg-muted hover:text-foreground",
                        )}
                      >
                        {slots * 30 < 60 ? `${slots * 30} min` : `${(slots * 30) / 60} h`}
                      </button>
                    ))}
                  </div>
                </div>
                <p className="text-xs text-muted-foreground">
                  {minutesToLabel(selectedInfo.minutes)} –{" "}
                  {minutesToLabel(selectedInfo.minutes + durationSlots * 30)} · Invite tout le groupe ({members.length} membre{members.length > 1 ? "s" : ""}).
                </p>
              </div>
              <DialogFooter>
                <Button variant="outline" size="sm" onClick={() => setCreatingOuting(false)} disabled={isPending}>
                  Retour
                </Button>
                <Button size="sm" onClick={submitOuting} disabled={isPending}>
                  {isPending ? "Envoi…" : "Envoyer l'invitation"}
                </Button>
              </DialogFooter>
            </>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
