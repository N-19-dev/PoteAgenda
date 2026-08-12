"use client";

import { useMemo } from "react";
import { format, isSameMonth, isToday } from "date-fns";
import { cn } from "@/lib/utils";
import { DAY_LABELS_SHORT, eventSlotRangeForDay, getMonthGridDates } from "@/lib/schedule";
import type { CalendarEvent, Outing } from "@/lib/supabase/types";

interface MonthItem {
  key: string;
  title: string;
  color: string;
}

interface MonthGridProps {
  monthStart: Date;
  events: CalendarEvent[];
  outings: Outing[];
  onSelectDay: (date: Date) => void;
}

const MAX_VISIBLE = 3;

export function MonthGrid({ monthStart, events, outings, onSelectDay }: MonthGridProps) {
  const days = useMemo(() => getMonthGridDates(monthStart), [monthStart]);

  const itemsByDay = useMemo(() => {
    const map = new Map<string, MonthItem[]>();
    for (const day of days) {
      const items: MonthItem[] = [];
      for (const event of events) {
        if (eventSlotRangeForDay(new Date(event.start_at), new Date(event.end_at), day)) {
          items.push({ key: event.id, title: event.title, color: event.color });
        }
      }
      for (const outing of outings) {
        if (eventSlotRangeForDay(new Date(outing.starts_at), new Date(outing.ends_at), day)) {
          items.push({ key: outing.id, title: outing.title, color: "var(--color-primary)" });
        }
      }
      map.set(day.toDateString(), items);
    }
    return map;
  }, [days, events, outings]);

  return (
    <div className="min-w-0 overflow-hidden rounded-xl border border-border/40 bg-card shadow-[0_1px_3px_rgba(0,0,0,0.05)]">
      <div className="grid grid-cols-7 border-b border-border/60">
        {DAY_LABELS_SHORT.map((label) => (
          <div key={label} className="py-1.5 text-center text-[10px] font-medium uppercase tracking-wide text-muted-foreground">
            {label}
          </div>
        ))}
      </div>
      <div className="grid grid-cols-7">
        {days.map((day) => {
          const inMonth = isSameMonth(day, monthStart);
          const items = itemsByDay.get(day.toDateString()) ?? [];
          const overflow = items.length - MAX_VISIBLE;
          return (
            <button
              key={day.toISOString()}
              type="button"
              onClick={() => onSelectDay(day)}
              className={cn(
                "flex min-h-16 min-w-0 flex-col items-stretch gap-0.5 border-b border-l border-border/30 p-1 text-left transition-colors first:border-l-0 hover:bg-accent [&:nth-child(7n+1)]:border-l-0",
                !inMonth && "bg-muted/30",
              )}
            >
              <span
                className={cn(
                  "flex size-5 items-center justify-center self-start rounded-full text-[11px] tabular-nums",
                  inMonth ? "text-foreground" : "text-muted-foreground/50",
                  isToday(day) && "bg-primary font-semibold text-primary-foreground",
                )}
              >
                {format(day, "d")}
              </span>
              <div className="flex min-w-0 flex-1 flex-col gap-0.5 overflow-hidden">
                {items.slice(0, MAX_VISIBLE).map((item) => (
                  <span
                    key={item.key}
                    className="min-w-0 truncate rounded border-l-2 px-1 py-0.5 text-[10px] font-medium leading-tight"
                    style={{
                      backgroundColor: `color-mix(in oklch, ${item.color} 12%, transparent)`,
                      borderColor: item.color,
                      color: item.color,
                    }}
                  >
                    {item.title}
                  </span>
                ))}
                {overflow > 0 && (
                  <span className="px-1 text-[10px] text-muted-foreground">+{overflow}</span>
                )}
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}
