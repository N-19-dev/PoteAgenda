import ical from "node-ical";
import { addDays } from "date-fns";

/** Horizon glissant sur lequel les événements récurrents sont expansés en occurrences concrètes. */
const HORIZON_DAYS = 180;
/** Couleur fixe des événements importés (distincte des couleurs de QUICK_LABELS pour l'agenda manuel). */
export const ICS_EVENT_COLOR = "#0ea5e9";
/** Taille max acceptée pour un flux .ics (fichier ou URL). */
export const MAX_ICS_BYTES = 5 * 1024 * 1024; // 5 Mo

export interface ParsedIcsEvent {
  title: string;
  start_at: string;
  end_at: string;
  external_uid: string;
}

function summaryToString(summary: unknown): string {
  if (!summary) return "Occupé";
  if (typeof summary === "string") return summary;
  if (typeof summary === "object" && summary !== null && "val" in summary) {
    return String((summary as { val: unknown }).val) || "Occupé";
  }
  return "Occupé";
}

/** Parse un contenu .ics en occurrences concrètes datées, en expansant les événements récurrents sur un horizon glissant. */
export function parseIcsToEvents(icsText: string): ParsedIcsEvent[] {
  const data = ical.sync.parseICS(icsText);
  const now = new Date();
  const horizonEnd = addDays(now, HORIZON_DAYS);
  const events: ParsedIcsEvent[] = [];

  for (const component of Object.values(data)) {
    if (!component || component.type !== "VEVENT" || !component.start) continue;

    const title = summaryToString(component.summary);
    const fallbackDurationMs = component.end
      ? component.end.getTime() - component.start.getTime()
      : 60 * 60 * 1000;

    if (component.rrule) {
      const instances = ical.expandRecurringEvent(component, { from: now, to: horizonEnd });
      for (const instance of instances) {
        const start = instance.start;
        const end = instance.end ?? new Date(start.getTime() + fallbackDurationMs);
        if (end <= start) continue;
        events.push({
          title: summaryToString(instance.summary) || title,
          start_at: start.toISOString(),
          end_at: end.toISOString(),
          external_uid: `${component.uid}-${start.toISOString()}`,
        });
      }
    } else {
      const start = component.start;
      const end = component.end ?? new Date(start.getTime() + fallbackDurationMs);
      if (end <= start) continue;
      if (end < now || start > horizonEnd) continue;
      events.push({
        title,
        start_at: start.toISOString(),
        end_at: end.toISOString(),
        external_uid: component.uid,
      });
    }
  }

  return events;
}

/**
 * Récupère un flux .ics distant côté serveur, avec timeout, vérification basique
 * du contenu et plafond de taille (l'URL est fournie par l'utilisateur : surface
 * SSRF-like à traiter prudemment).
 */
export async function fetchIcsFromUrl(url: string): Promise<string> {
  let parsed: URL;
  try {
    parsed = new URL(url.replace(/^webcal:\/\//i, "https://"));
  } catch {
    throw new Error("URL invalide");
  }
  if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
    throw new Error("URL invalide");
  }

  const response = await fetch(parsed.toString(), {
    signal: AbortSignal.timeout(10_000),
    redirect: "follow",
  });
  if (!response.ok) throw new Error(`Impossible de récupérer le calendrier (HTTP ${response.status})`);

  const contentLength = response.headers.get("content-length");
  if (contentLength && Number(contentLength) > MAX_ICS_BYTES) {
    throw new Error("Le calendrier distant est trop volumineux");
  }

  const text = await response.text();
  if (text.length > MAX_ICS_BYTES) throw new Error("Le calendrier distant est trop volumineux");
  if (!text.includes("BEGIN:VCALENDAR")) throw new Error("Le contenu récupéré n'est pas un calendrier .ics valide");

  return text;
}
