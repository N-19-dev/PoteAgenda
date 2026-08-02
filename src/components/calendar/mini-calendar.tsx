"use client";

import { useState } from "react";
import { addMonths, format, isSameDay, isSameMonth, isToday } from "date-fns";
import { fr } from "date-fns/locale";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { cn } from "@/lib/utils";
import { DAY_LABELS_SHORT, getMonthGridDates, getMonthStart } from "@/lib/schedule";

interface MiniCalendarProps {
  selected: Date;
  onSelect: (date: Date) => void;
}

/** Petit sélecteur de mois pour naviguer la vue principale — repère "aujourd'hui" et le jour sélectionné. */
export function MiniCalendar({ selected, onSelect }: MiniCalendarProps) {
  const [displayedMonth, setDisplayedMonth] = useState(() => getMonthStart(selected));
  const [trackedSelected, setTrackedSelected] = useState(selected);

  if (!isSameMonth(trackedSelected, selected)) {
    setTrackedSelected(selected);
    setDisplayedMonth(getMonthStart(selected));
  }

  const days = getMonthGridDates(displayedMonth);

  return (
    <div className="rounded-xl border border-border bg-card p-3">
      <div className="mb-2 flex items-center justify-between">
        <span className="text-sm font-semibold capitalize">
          {format(displayedMonth, "MMMM yyyy", { locale: fr })}
        </span>
        <div className="flex items-center gap-0.5">
          <button
            type="button"
            aria-label="Mois précédent"
            onClick={() => setDisplayedMonth((m) => addMonths(m, -1))}
            className="flex size-6 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
          >
            <ChevronLeft className="h-3.5 w-3.5" />
          </button>
          <button
            type="button"
            aria-label="Mois suivant"
            onClick={() => setDisplayedMonth((m) => addMonths(m, 1))}
            className="flex size-6 items-center justify-center rounded-md text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
          >
            <ChevronRight className="h-3.5 w-3.5" />
          </button>
        </div>
      </div>

      <div className="grid grid-cols-7 gap-y-1 text-center">
        {DAY_LABELS_SHORT.map((d) => (
          <span key={d} className="text-[10px] font-medium text-muted-foreground">
            {d.slice(0, 1)}
          </span>
        ))}
        {days.map((day) => {
          const inMonth = isSameMonth(day, displayedMonth);
          const isSelected = isSameDay(day, selected);
          const today = isToday(day);
          return (
            <button
              key={day.toISOString()}
              type="button"
              onClick={() => onSelect(day)}
              className={cn(
                "mx-auto flex size-7 items-center justify-center rounded-full text-[12px] tabular-nums transition-colors",
                !inMonth && "text-muted-foreground/40",
                inMonth && !isSelected && "text-foreground hover:bg-muted",
                today && !isSelected && "font-semibold text-primary",
                isSelected && "bg-primary font-semibold text-primary-foreground",
              )}
            >
              {format(day, "d")}
            </button>
          );
        })}
      </div>
    </div>
  );
}
