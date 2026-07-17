import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { ICS_EVENT_COLOR, MAX_ICS_BYTES, fetchIcsFromUrl, parseIcsToEvents } from "@/lib/ics";

export async function POST(request: NextRequest) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Non authentifié" }, { status: 401 });

  const contentType = request.headers.get("content-type") ?? "";
  let label: string;
  let kind: "file" | "url";
  let icsUrl: string | null = null;
  let icsText: string;

  try {
    if (contentType.includes("multipart/form-data")) {
      const formData = await request.formData();
      const file = formData.get("file");
      const labelInput = formData.get("label");
      if (!(file instanceof File)) throw new Error("Fichier manquant");
      if (file.size > MAX_ICS_BYTES) throw new Error("Le fichier est trop volumineux");
      icsText = await file.text();
      if (!icsText.includes("BEGIN:VCALENDAR")) throw new Error("Le fichier n'est pas un .ics valide");
      label = typeof labelInput === "string" && labelInput.trim() ? labelInput.trim() : file.name;
      kind = "file";
    } else {
      const body = await request.json();
      const rawUrl = typeof body.ics_url === "string" ? body.ics_url.trim() : "";
      const labelInput = typeof body.label === "string" ? body.label.trim() : "";
      if (!rawUrl) throw new Error("URL manquante");
      icsText = await fetchIcsFromUrl(rawUrl);
      label = labelInput || "Calendrier";
      kind = "url";
      icsUrl = rawUrl;
    }
  } catch (err) {
    return NextResponse.json(
      { error: err instanceof Error ? err.message : "Import impossible" },
      { status: 400 },
    );
  }

  try {
    const events = parseIcsToEvents(icsText).map((e) => ({ ...e, color: ICS_EVENT_COLOR }));

    const { data: source, error: sourceError } = await supabase
      .from("calendar_sources")
      .insert({ user_id: user.id, label, kind, ics_url: icsUrl })
      .select()
      .single();
    if (sourceError || !source) {
      console.error("calendar_sources insert error:", sourceError);
      return NextResponse.json({ error: "Impossible de créer la source" }, { status: 500 });
    }

    const { error: rpcError } = await supabase.rpc("resync_calendar_source", {
      p_source_id: source.id,
      p_events: events,
    });
    if (rpcError) {
      console.error("resync_calendar_source rpc error:", rpcError);
      return NextResponse.json({ error: "Import du calendrier impossible" }, { status: 500 });
    }

    return NextResponse.json({ source, imported: events.length });
  } catch (err) {
    console.error("calendar-sources POST unexpected error:", err);
    return NextResponse.json({ error: "Import impossible (erreur interne)" }, { status: 500 });
  }
}
