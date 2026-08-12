"use client";

import { Fragment, useCallback, useEffect, useRef, useState } from "react";
import { format, isToday } from "date-fns";
import { fr } from "date-fns/locale";
import { ChevronDown, ChevronUp } from "lucide-react";
import { cn } from "@/lib/utils";
import {
  NIGHT_SLOT_COUNT,
  SLOTS_PER_DAY,
  SLOT_MINUTES,
  minutesToLabel,
  slotIndexToMinutes,
} from "@/lib/schedule";

export interface SlotSelection {
  day: number;
  startSlot: number;
  endSlot: number;
}

interface WeekGridProps {
  weekDates: Date[];
  cellClassName: (day: number, slotIndex: number) => string;
  cellContent?: (day: number, slotIndex: number) => React.ReactNode;
  onCellTap?: (day: number, slotIndex: number) => void;
  onRangeSelect?: (selection: SlotSelection) => void;
  interactive?: boolean;
}

export const ROW_HEIGHT = 22;

function useNowMinutes() {
  const [minutes, setMinutes] = useState<number | null>(null);
  useEffect(() => {
    const update = () => setMinutes(new Date().getHours() * 60 + new Date().getMinutes());
    update();
    const id = setInterval(update, 60_000);
    return () => clearInterval(id);
  }, []);
  return minutes;
}

/** Grille compacte : la lecture du temps prime, la nuit (0h-8h) est repliée par défaut. */
export function WeekGrid({
  weekDates,
  cellClassName,
  cellContent,
  onCellTap,
  onRangeSelect,
  interactive = false,
}: WeekGridProps) {
  const [dragStart, setDragStart] = useState<{ day: number; slot: number } | null>(null);
  const [dragEnd, setDragEnd] = useState<number | null>(null);
  const [nightOpen, setNightOpen] = useState(false);
  const dragging = useRef(false);
  const nowMinutes = useNowMinutes();

  const visibleSlots = Array.from(
    { length: SLOTS_PER_DAY - (nightOpen ? 0 : NIGHT_SLOT_COUNT) },
    (_, i) => i + (nightOpen ? 0 : NIGHT_SLOT_COUNT),
  );

  const finishDrag = useCallback(() => {
    if (!interactive || !dragging.current || !dragStart || dragEnd === null) {
      dragging.current = false;
      return;
    }
    onRangeSelect?.({
      day: dragStart.day,
      startSlot: Math.min(dragStart.slot, dragEnd),
      endSlot: Math.max(dragStart.slot, dragEnd) + 1,
    });
    dragging.current = false;
    setDragStart(null);
    setDragEnd(null);
  }, [dragEnd, dragStart, interactive, onRangeSelect]);

  const selected = (day: number, slot: number) =>
    dragStart?.day === day &&
    dragEnd !== null &&
    slot >= Math.min(dragStart.slot, dragEnd) &&
    slot <= Math.max(dragStart.slot, dragEnd);

  const handlePointerMove = useCallback(
    (event: React.PointerEvent) => {
      if (!interactive || !dragging.current || !dragStart) return;
      const target = document.elementFromPoint(event.clientX, event.clientY) as HTMLElement | null;
      const cell = target?.closest<HTMLElement>("[data-day][data-slot]");
      if (!cell) return;
      const day = Number(cell.dataset.day);
      const slot = Number(cell.dataset.slot);
      if (day !== dragStart.day) return;
      setDragEnd(slot);
    },
    [dragStart, interactive],
  );

  const todayIndex = weekDates.findIndex((d) => isToday(d));
  const nowLine =
    todayIndex >= 0 && nowMinutes !== null && (nightOpen || nowMinutes >= slotIndexToMinutes(NIGHT_SLOT_COUNT))
      ? { column: todayIndex + 2, row: 3 + (Math.floor(nowMinutes / SLOT_MINUTES) - visibleSlots[0]), offset: ((nowMinutes % SLOT_MINUTES) / SLOT_MINUTES) * ROW_HEIGHT }
      : null;

  return (
    <div
      className="overflow-auto rounded-xl border border-border/40 bg-card shadow-[0_1px_3px_rgba(0,0,0,0.05)]"
      onPointerMove={handlePointerMove}
      onPointerUp={finishDrag}
      onPointerLeave={finishDrag}
    >
      <div
        className="relative grid select-none"
        style={{
          gridTemplateColumns: `48px repeat(${weekDates.length}, minmax(64px, 1fr))`,
          minWidth: weekDates.length > 1 ? "560px" : undefined,
        }}
      >
        <div className="sticky left-0 top-0 z-20 border-b border-border bg-card" />
        {weekDates.map((date) => (
          <div
            key={date.toISOString()}
            className={cn(
              "sticky top-0 z-10 border-b border-l border-border/60 bg-card py-1.5 text-center",
            )}
          >
            <div className="text-[10px] font-medium uppercase tracking-wide text-muted-foreground">
              {format(date, "EEE", { locale: fr })}
            </div>
            <div
              className={cn(
                "mx-auto mt-0.5 flex size-6 items-center justify-center rounded-full text-[13px] font-semibold tabular-nums",
                isToday(date) && "bg-primary text-primary-foreground",
              )}
            >
              {format(date, "d")}
            </div>
          </div>
        ))}

        {/* Bandeau nuit repliable (0h-8h) */}
        <button
          type="button"
          onClick={() => setNightOpen((v) => !v)}
          className="col-span-full flex items-center justify-center gap-1 border-t border-border bg-muted/40 py-1 text-[10px] font-medium text-muted-foreground transition-colors hover:bg-muted/70"
        >
          {nightOpen ? (
            <>
              <ChevronUp className="h-3 w-3" /> Replier la nuit (0h–8h)
            </>
          ) : (
            <>
              <ChevronDown className="h-3 w-3" /> Nuit repliée (0h–8h)
            </>
          )}
        </button>

        <div
          className="sticky left-0 z-10 bg-card"
          style={{ gridColumn: 1, gridRow: `3 / span ${visibleSlots.length}` }}
        >
          {visibleSlots.map((slot) => {
            const minutes = slotIndexToMinutes(slot);
            const hour = minutes % 60 === 0;
            return (
              <div
                key={slot}
                className={cn(
                  "border-t pr-2 text-right font-mono text-[11px] text-muted-foreground",
                  hour ? "border-border/50" : "border-transparent",
                )}
                style={{ height: ROW_HEIGHT }}
              >
                {hour && <span className="relative -top-2 block">{minutesToLabel(minutes)}</span>}
              </div>
            );
          })}
        </div>

        {visibleSlots.map((slot) => {
          const minutes = slotIndexToMinutes(slot);
          const hour = minutes % 60 === 0;
          return (
            <Fragment key={slot}>
              {weekDates.map((_, day) => (
                <div
                  key={`${day}-${slot}`}
                  data-day={day}
                  data-slot={slot}
                  style={{ height: ROW_HEIGHT, touchAction: interactive ? "none" : undefined }}
                  onPointerDown={() => {
                    if (interactive) {
                      dragging.current = true;
                      setDragStart({ day, slot });
                      setDragEnd(slot);
                    }
                  }}
                  onClick={() => onCellTap?.(day, slot)}
                  className={cn(
                    "relative border-l border-t border-border/25",
                    hour ? "border-t-border/50" : "border-t-transparent",
                    interactive && "cursor-pointer hover:bg-accent",
                    cellClassName(day, slot),
                    selected(day, slot) && "bg-accent",
                  )}
                >
                  {cellContent?.(day, slot)}
                </div>
              ))}
            </Fragment>
          );
        })}

        {nowLine && (
          <div
            className="pointer-events-none z-10 flex items-center"
            style={{
              gridColumn: nowLine.column,
              gridRow: nowLine.row,
              marginTop: nowLine.offset,
              height: 0,
            }}
          >
            <span className="-ml-1 h-1.5 w-1.5 shrink-0 rounded-full bg-primary" />
            <span className="h-px w-full bg-primary" />
          </div>
        )}
      </div>
    </div>
  );
}

export function hoursLegend() {
  return { SLOT_MINUTES };
}
