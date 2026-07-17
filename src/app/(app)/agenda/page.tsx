import Link from "next/link";
import { addDays } from "date-fns";
import { CalendarCog } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { AgendaEditor } from "@/components/agenda/agenda-editor";
import { parseWeekParam } from "@/lib/schedule";
import type { CalendarEvent } from "@/lib/supabase/types";

interface PageProps {
  searchParams: Promise<{ week?: string }>;
}

export default async function AgendaPage({ searchParams }: PageProps) {
  const { week } = await searchParams;
  const weekStart = parseWeekParam(week);
  const weekEnd = addDays(weekStart, 7);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: events } = await supabase
    .from("calendar_events")
    .select("*")
    .eq("user_id", user!.id)
    .lt("start_at", weekEnd.toISOString())
    .gt("end_at", weekStart.toISOString())
    .order("start_at");

  return (
    <div className="space-y-4">
      <div className="flex items-start justify-between gap-2">
        <div>
          <h1 className="text-xl font-semibold tracking-tight">Mon agenda</h1>
          <p className="text-sm text-muted-foreground">
            Tes indisponibilités. Tes amis ne voient jamais le titre — seulement « Occupé ».
          </p>
        </div>
        <Link
          href="/agenda/calendars"
          className="flex shrink-0 items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground"
        >
          <CalendarCog className="h-4 w-4" />
          Mes calendriers
        </Link>
      </div>
      <AgendaEditor weekStart={weekStart} events={(events ?? []) as CalendarEvent[]} />
    </div>
  );
}
