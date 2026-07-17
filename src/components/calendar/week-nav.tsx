"use client";

import { useRouter, usePathname } from "next/navigation";
import { addDays, format, isSameDay } from "date-fns";
import { fr } from "date-fns/locale";
import { ChevronLeft, ChevronRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { dateKey, getWeekStart } from "@/lib/schedule";

export function WeekNav({ weekStart }: { weekStart: Date }) {
  const router = useRouter();
  const pathname = usePathname();

  function go(target: Date) {
    router.push(`${pathname}?week=${dateKey(target)}`);
  }

  const weekEnd = addDays(weekStart, 6);
  const isCurrentWeek = isSameDay(weekStart, getWeekStart(new Date()));

  return (
    <div className="flex items-center justify-between gap-2">
      <Button
        variant="outline"
        size="icon"
        onClick={() => go(addDays(weekStart, -7))}
        aria-label="Semaine précédente"
      >
        <ChevronLeft className="h-4 w-4" />
      </Button>

      <div className="flex items-center gap-2 text-sm font-medium">
        <span>
          {format(weekStart, "d MMM", { locale: fr })} – {format(weekEnd, "d MMM", { locale: fr })}
        </span>
        {!isCurrentWeek && (
          <Button
            variant="ghost"
            size="sm"
            className="h-7 px-2 text-xs"
            onClick={() => go(getWeekStart(new Date()))}
          >
            Aujourd&apos;hui
          </Button>
        )}
      </div>

      <Button
        variant="outline"
        size="icon"
        onClick={() => go(addDays(weekStart, 7))}
        aria-label="Semaine suivante"
      >
        <ChevronRight className="h-4 w-4" />
      </Button>
    </div>
  );
}
