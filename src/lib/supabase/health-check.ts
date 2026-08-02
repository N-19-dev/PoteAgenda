export async function ensureSupabaseReachable() {
  const response = await fetch("/api/supabase-health", {
    cache: "no-store",
  });

  if (!response.ok) {
    throw new Error("supabase-unreachable");
  }
}
