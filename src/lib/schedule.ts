import { addDays, addMinutes, differenceInMinutes, format, startOfDay, startOfWeek } from "date-fns";
import type { BusyEvent } from "@/lib/supabase/types";

export const DAY_LABELS_SHORT = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"] as const;
export const DAY_LABELS_FULL = [
  "Lundi",
  "Mardi",
  "Mercredi",
  "Jeudi",
  "Vendredi",
  "Samedi",
  "Dimanche",
] as const;

/** Plage horaire affichée dans la grille hebdomadaire. */
export const GRID_START_HOUR = 7;
export const GRID_END_HOUR = 24;
export const SLOT_MINUTES = 30;
export const SLOTS_PER_DAY = ((GRID_END_HOUR - GRID_START_HOUR) * 60) / SLOT_MINUTES;

export function minutesToLabel(totalMinutes: number): string {
  const h = Math.floor(totalMinutes / 60);
  const m = totalMinutes % 60;
  return `${String(h).padStart(2, "0")}:${String(m).padStart(2, "0")}`;
}

/** Index de créneau (0..SLOTS_PER_DAY-1) relatif à GRID_START_HOUR. */
export function slotIndexToMinutes(slotIndex: number): number {
  return GRID_START_HOUR * 60 + slotIndex * SLOT_MINUTES;
}

/** Lundi de la semaine contenant `date` (par défaut : aujourd'hui). */
export function getWeekStart(date: Date = new Date()): Date {
  return startOfWeek(date, { weekStartsOn: 1 });
}

/** Les 7 dates (Lun..Dim) de la semaine commençant à `weekStart`. */
export function getWeekDates(weekStart: Date): Date[] {
  return Array.from({ length: 7 }, (_, i) => addDays(weekStart, i));
}

export function dateKey(date: Date): string {
  return format(date, "yyyy-MM-dd");
}

/** Parse le paramètre d'URL `?week=yyyy-MM-dd` en lundi de semaine ; retombe sur la semaine courante si absent/invalide. */
export function parseWeekParam(param?: string): Date {
  if (param) {
    const parsed = new Date(`${param}T00:00:00`);
    if (!Number.isNaN(parsed.getTime())) return getWeekStart(parsed);
  }
  return getWeekStart(new Date());
}

export interface DaySlotGrid {
  /** grid[dayIndex][slotIndex] = nombre de membres occupés sur ce créneau */
  busyCounts: number[][];
  /** grid[dayIndex][slotIndex] = ids des membres occupés sur ce créneau */
  busyMembers: string[][][];
}

/**
 * Découpe le chevauchement d'un événement daté avec un jour donné de la
 * grille en index de créneaux (slots), clippé à [GRID_START_HOUR, GRID_END_HOUR).
 * Gère les événements qui chevauchent minuit en clippant par jour affiché.
 */
export function eventSlotRangeForDay(
  startAt: Date,
  endAt: Date,
  day: Date,
): { startSlot: number; endSlot: number } | null {
  const dayStart = startOfDay(day);
  const dayEnd = addDays(dayStart, 1);
  const overlapStart = startAt > dayStart ? startAt : dayStart;
  const overlapEnd = endAt < dayEnd ? endAt : dayEnd;
  if (overlapStart >= overlapEnd) return null;

  const startMin = Math.max(differenceInMinutes(overlapStart, dayStart), GRID_START_HOUR * 60);
  const endMin = Math.min(differenceInMinutes(overlapEnd, dayStart), GRID_END_HOUR * 60);
  if (startMin >= endMin) return null;

  const startSlot = Math.floor((startMin - GRID_START_HOUR * 60) / SLOT_MINUTES);
  const endSlot = Math.ceil((endMin - GRID_START_HOUR * 60) / SLOT_MINUTES);
  return { startSlot: Math.max(0, startSlot), endSlot: Math.min(SLOTS_PER_DAY, endSlot) };
}

/**
 * Construit, pour chaque date de la semaine affichée et chaque créneau de
 * 30 min, le nombre (et la liste) de membres occupés — sans jamais
 * manipuler de titre d'événement (les BusyEvent n'en contiennent pas).
 */
export function buildBusyGrid(busyEvents: BusyEvent[], weekDates: Date[]): DaySlotGrid {
  const busyCounts: number[][] = Array.from({ length: 7 }, () => Array(SLOTS_PER_DAY).fill(0));
  const busyMembers: string[][][] = Array.from({ length: 7 }, () =>
    Array.from({ length: SLOTS_PER_DAY }, () => []),
  );

  for (const event of busyEvents) {
    const startAt = new Date(event.start_at);
    const endAt = new Date(event.end_at);
    weekDates.forEach((day, dayIndex) => {
      const range = eventSlotRangeForDay(startAt, endAt, day);
      if (!range) return;
      for (let i = range.startSlot; i < range.endSlot; i++) {
        if (!busyMembers[dayIndex][i].includes(event.user_id)) {
          busyMembers[dayIndex][i].push(event.user_id);
          busyCounts[dayIndex][i] += 1;
        }
      }
    });
  }

  return { busyCounts, busyMembers };
}

/** Convertit une plage de créneaux sur une date concrète en timestamps ISO. */
export function slotRangeToTimes(date: Date, startSlot: number, endSlot: number) {
  const dayStart = startOfDay(date);
  return {
    start_at: addMinutes(dayStart, slotIndexToMinutes(startSlot)).toISOString(),
    end_at: addMinutes(dayStart, slotIndexToMinutes(endSlot)).toISOString(),
  };
}

export const QUICK_LABELS = [
  { label: "Travail", color: "#6366f1" },
  { label: "Sport", color: "#f97316" },
  { label: "Cours", color: "#eab308" },
  { label: "Dodo", color: "#64748b" },
  { label: "Autre", color: "#ec4899" },
] as const;

export type SlotStatus = "free-all" | "busy-partial" | "busy-all";

export function slotStatus(busyCount: number, totalMembers: number): SlotStatus {
  if (busyCount === 0) return "free-all";
  if (busyCount >= totalMembers) return "busy-all";
  return "busy-partial";
}
