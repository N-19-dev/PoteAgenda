"use client";

import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

const HOURS = Array.from({ length: 24 }, (_, h) => String(h).padStart(2, "0"));
const MINUTES = ["00", "15", "30", "45"];

export type DateTimeParts = { date: string; hour: string; minute: string };
export const emptyDateTimeParts: DateTimeParts = { date: "", hour: "", minute: "" };

export function dateTimePartsToISOString({ date, hour, minute }: DateTimeParts): string {
  return new Date(`${date}T${hour}:${minute}:00`).toISOString();
}

export function isoStringToDateTimeParts(value: string): DateTimeParts {
  const date = new Date(value);
  const offset = date.getTimezoneOffset() * 60_000;
  const local = new Date(date.getTime() - offset).toISOString();
  return { date: local.slice(0, 10), hour: local.slice(11, 13), minute: local.slice(14, 16) };
}

export const DURATION_PRESETS_MIN = [30, 60, 90, 120, 180];

export function addMinutesToDateTimeParts(value: DateTimeParts, minutes: number): DateTimeParts {
  const start = new Date(`${value.date}T${value.hour}:${value.minute}:00`);
  const end = new Date(start.getTime() + minutes * 60_000);
  const offset = end.getTimezoneOffset() * 60_000;
  const local = new Date(end.getTime() - offset).toISOString();
  return { date: local.slice(0, 10), hour: local.slice(11, 13), minute: local.slice(14, 16) };
}

export function DateTimeFields({
  legend,
  idPrefix,
  value,
  onChange,
}: {
  legend: string;
  idPrefix: string;
  value: DateTimeParts;
  onChange: (value: DateTimeParts) => void;
}) {
  return (
    <div className="space-y-1.5">
      <Label htmlFor={`${idPrefix}-date`}>{legend}</Label>
      <div className="grid grid-cols-[1fr_auto_auto] gap-2">
        <Input
          id={`${idPrefix}-date`}
          type="date"
          value={value.date}
          onChange={(e) => onChange({ ...value, date: e.target.value })}
          required
        />
        <select
          aria-label={`${legend} — heure`}
          value={value.hour}
          onChange={(e) => onChange({ ...value, hour: e.target.value })}
          required
          className="h-9 rounded-md border border-input bg-background px-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          <option value="" disabled>hh</option>
          {HOURS.map((h) => <option key={h} value={h}>{h}</option>)}
        </select>
        <select
          aria-label={`${legend} — minute`}
          value={value.minute}
          onChange={(e) => onChange({ ...value, minute: e.target.value })}
          required
          className="h-9 rounded-md border border-input bg-background px-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
        >
          <option value="" disabled>mm</option>
          {MINUTES.map((m) => <option key={m} value={m}>{m}</option>)}
        </select>
      </div>
    </div>
  );
}
