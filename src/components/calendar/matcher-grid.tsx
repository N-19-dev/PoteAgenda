"use client";

import { useMemo, useState } from "react";
import { format } from "date-fns";
import { fr } from "date-fns/locale";
import { WeekGrid } from "@/components/calendar/week-grid";
import { WeekNav } from "@/components/calendar/week-nav";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { cn } from "@/lib/utils";
import { buildBusyGrid, getWeekDates, minutesToLabel, slotIndexToMinutes, slotStatus } from "@/lib/schedule";
import type { BusyEvent, Profile } from "@/lib/supabase/types";
import { Check, X } from "lucide-react";

interface MatcherGridProps {
  weekStart: Date;
  members: Profile[];
  busyEvents: BusyEvent[];
}

export function MatcherGrid({ weekStart, members, busyEvents }: MatcherGridProps) {
  const [selected, setSelected] = useState<{ day: number; slot: number } | null>(null);

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
          if (!open) setSelected(null);
        }}
      >
        <DialogContent>
          {selectedInfo && (
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
            </>
          )}
        </DialogContent>
      </Dialog>
    </div>
  );
}
