"use client";

import { useRouter, usePathname, useSearchParams } from "next/navigation";
import { isSameDay } from "date-fns";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { addViewStep, dateKey, type CalendarView } from "@/lib/schedule";

const VIEW_LABELS: Record<CalendarView, string> = {
  day: "Jour",
  week: "Semaine",
  month: "Mois",
};

export function CalendarNav({ view, date }: { view: CalendarView; date: Date }) {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  function pushParams(next: { view?: CalendarView; date?: Date }) {
    const params = new URLSearchParams(searchParams.toString());
    if (next.view) params.set("view", next.view);
    if (next.date) params.set("date", dateKey(next.date));
    router.push(`${pathname}?${params.toString()}`, { scroll: false });
  }

  const isToday = isSameDay(date, new Date());

  return (
    <div className="glass-panel flex flex-wrap items-center justify-between gap-2 rounded-xl px-2 py-1.5">
      <div className="flex items-center gap-1">
        <Button variant="ghost" size="icon" className="group" onClick={() => pushParams({ date: addViewStep(view, date, -1) })} aria-label="Précédent">
          <ChevronLeft className="h-4 w-4 transition-transform group-hover:-translate-x-0.5" />
        </Button>
        {!isToday && (
          <Button variant="ghost" size="sm" className="h-8 px-2 text-xs text-primary" onClick={() => pushParams({ date: new Date() })}>
            Aujourd&apos;hui
          </Button>
        )}
        <Button variant="ghost" size="icon" className="group" onClick={() => pushParams({ date: addViewStep(view, date, 1) })} aria-label="Suivant">
          <ChevronRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" />
        </Button>
      </div>

      <div className="flex rounded-lg bg-muted p-0.5 text-xs">
        {(Object.keys(VIEW_LABELS) as CalendarView[]).map((v) => (
          <button
            key={v}
            type="button"
            onClick={() => pushParams({ view: v })}
            className={cn(
              "rounded-md px-2.5 py-1 font-medium transition-colors",
              view === v ? "bg-card text-foreground shadow-sm" : "text-muted-foreground hover:text-foreground",
            )}
          >
            {VIEW_LABELS[v]}
          </button>
        ))}
      </div>
    </div>
  );
}
