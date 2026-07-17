"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

export async function deleteCalendarSource(id: string) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) throw new Error("Non authentifié");

  const { error } = await supabase.from("calendar_sources").delete().eq("id", id);
  if (error) throw error;
  revalidatePath("/agenda/calendars");
  revalidatePath("/agenda");
}
