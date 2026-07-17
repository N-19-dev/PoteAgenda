"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function addCalendarEvent(input: {
  title: string;
  start_at: string;
  end_at: string;
  color: string;
}) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Non authentifié");

  const { error } = await supabase
    .from("calendar_events")
    .insert({ ...input, user_id: user.id, source: "manual" });
  if (error) throw error;
  revalidatePath("/agenda");
}

export async function deleteCalendarEvent(id: string) {
  const supabase = await createClient();
  const { error } = await supabase.from("calendar_events").delete().eq("id", id);
  if (error) throw error;
  revalidatePath("/agenda");
}
