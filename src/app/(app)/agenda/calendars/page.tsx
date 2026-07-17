import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { CalendarSourcesManager } from "@/components/agenda/calendar-sources-manager";
import type { CalendarSource } from "@/lib/supabase/types";

export default async function CalendarsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: sources } = await supabase
    .from("calendar_sources")
    .select("*")
    .eq("user_id", user!.id)
    .order("created_at");

  return (
    <div className="space-y-4">
      <Link
        href="/agenda"
        className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
      >
        <ArrowLeft className="h-4 w-4" />
        Mon agenda
      </Link>

      <div>
        <h1 className="text-xl font-semibold tracking-tight">Mes calendriers</h1>
        <p className="text-sm text-muted-foreground">
          Importe un calendrier externe (.ics) pour remplir automatiquement tes indisponibilités.
        </p>
      </div>

      <CalendarSourcesManager sources={(sources ?? []) as CalendarSource[]} />
    </div>
  );
}
