import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { ICS_EVENT_COLOR, fetchIcsFromUrl, parseIcsToEvents } from "@/lib/ics";

export async function POST(_request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Non authentifié" }, { status: 401 });

  const { data: source } = await supabase
    .from("calendar_sources")
    .select("*")
    .eq("id", id)
    .eq("user_id", user.id)
    .single();
  if (!source) return NextResponse.json({ error: "Calendrier introuvable" }, { status: 404 });
  if (source.kind !== "url" || !source.ics_url) {
    return NextResponse.json(
      { error: "Ce calendrier ne peut pas être resynchronisé (import par fichier)" },
      { status: 400 },
    );
  }

  let icsText: string;
  try {
    icsText = await fetchIcsFromUrl(source.ics_url);
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : "Resynchronisation impossible" },
      { status: 400 },
    );
  }

  const events = parseIcsToEvents(icsText).map((e) => ({ ...e, color: ICS_EVENT_COLOR }));

  const { error: rpcError } = await supabase.rpc("resync_calendar_source", {
    p_source_id: id,
    p_events: events,
  });
  if (rpcError) {
    return NextResponse.json({ error: "Resynchronisation impossible" }, { status: 500 });
  }

  return NextResponse.json({ imported: events.length });
}
