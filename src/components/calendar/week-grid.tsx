"use client";

import { Fragment, useCallback, useRef, useState } from "react";
import { format, isToday } from "date-fns";
import { cn } from "@/lib/utils";
import {
  DAY_LABELS_SHORT,
  GRID_START_HOUR,
  GRID_END_HOUR,
  SLOTS_PER_DAY,
  slotIndexToMinutes,
  minutesToLabel,
} from "@/lib/schedule";

export interface SlotSelection {
  day: number;
  startSlot: number;
  endSlot: number; // exclusif
}

interface WeekGridProps {
  /** Les 7 dates (Lun..Dim) de la semaine affichée. */
  weekDates: Date[];
  /** Classe(s) CSS appliquée(s) à une cellule (couleur "libre pour tous", etc). */
  cellClassName: (day: number, slotIndex: number) => string;
  /** Contenu optionnel affiché dans la cellule (ex: avatars). */
  cellContent?: (day: number, slotIndex: number) => React.ReactNode;
  /** Simple tap sur une cellule (utilisé en lecture seule pour la vue Matcher). */
  onCellTap?: (day: number, slotIndex: number) => void;
  /** Sélection par glisser (utilisé pour saisir une indisponibilité perso). */
  onRangeSelect?: (selection: SlotSelection) => void;
  interactive?: boolean;
}

const ROW_HEIGHT = 26; // px

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
  const isDragging = useRef(false);

  const slots = Array.from({ length: SLOTS_PER_DAY }, (_, i) => i);

  const handlePointerDown = useCallback(
    (day: number, slot: number) => {
      if (!interactive) return;
      isDragging.current = true;
      setDragStart({ day, slot });
      setDragEnd(slot);
    },
    [interactive],
  );

  const handlePointerEnter = useCallback(
    (day: number, slot: number) => {
      if (!interactive || !isDragging.current || !dragStart || dragStart.day !== day) return;
      setDragEnd(slot);
    },
    [interactive, dragStart],
  );

  const handlePointerUp = useCallback(() => {
    if (!interactive || !isDragging.current || !dragStart || dragEnd === null) {
      isDragging.current = false;
      return;
    }
    isDragging.current = false;
    const startSlot = Math.min(dragStart.slot, dragEnd);
    const endSlot = Math.max(dragStart.slot, dragEnd) + 1;
    onRangeSelect?.({ day: dragStart.day, startSlot, endSlot });
    setDragStart(null);
    setDragEnd(null);
  }, [interactive, dragStart, dragEnd, onRangeSelect]);

  const isInDragRange = (day: number, slot: number) => {
    if (!dragStart || dragEnd === null || dragStart.day !== day) return false;
    const min = Math.min(dragStart.slot, dragEnd);
    const max = Math.max(dragStart.slot, dragEnd);
    return slot >= min && slot <= max;
  };

  return (
    <div
      className="relative overflow-auto rounded-lg border border-border"
      style={{ maxHeight: "70vh" }}
      onPointerUp={handlePointerUp}
      onPointerLeave={handlePointerUp}
    >
      <div
        className="grid select-none"
        style={{ gridTemplateColumns: "36px repeat(7, minmax(38px, 1fr))" }}
      >
        {/* Header sticky */}
        <div className="sticky top-0 left-0 z-20 bg-card" />
        {weekDates.map((date, i) => (
          <div
            key={date.toISOString()}
            className={cn(
              "sticky top-0 z-10 border-b border-l border-border bg-card py-1.5 text-center text-[11px] font-medium text-muted-foreground",
              isToday(date) && "text-foreground",
            )}
          >
            {DAY_LABELS_SHORT[i]} <span className="text-[10px]">{format(date, "d")}</span>
          </div>
        ))}

        {/* Corps : une ligne par créneau de 30 min */}
        {slots.map((slot) => {
          const minutes = slotIndexToMinutes(slot);
          const isHourStart = minutes % 60 === 0;
          return (
            <Fragment key={slot}>
              <div
                key={`gutter-${slot}`}
                className="sticky left-0 z-10 bg-card pr-1 text-right text-[10px] text-muted-foreground"
                style={{ height: ROW_HEIGHT }}
              >
                {isHourStart ? (
                  <span className="relative -top-1.5">{minutesToLabel(minutes)}</span>
                ) : null}
              </div>
              {Array.from({ length: 7 }, (_, day) => (
                <div
                  key={`${day}-${slot}`}
                  onPointerDown={() => handlePointerDown(day, slot)}
                  onPointerEnter={() => handlePointerEnter(day, slot)}
                  onClick={() => onCellTap?.(day, slot)}
                  className={cn(
                    "border-l border-t border-border/60 transition-colors",
                    isHourStart && "border-t-border",
                    interactive && "cursor-pointer active:opacity-80",
                    onCellTap && !interactive && "cursor-pointer",
                    isInDragRange(day, slot) && "bg-primary/40",
                    cellClassName(day, slot),
                  )}
                  style={{ height: ROW_HEIGHT }}
                >
                  {cellContent?.(day, slot)}
                </div>
              ))}
            </Fragment>
          );
        })}
      </div>
    </div>
  );
}

export function hoursLegend() {
  return { GRID_START_HOUR, GRID_END_HOUR };
}
