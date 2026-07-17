import { createBrowserClient } from "@supabase/ssr";

// NB: pas de generic <Database> ici — voir le commentaire en tête de
// src/lib/supabase/types.ts. Le typage métier est assuré côté appelant via
// les interfaces de ce fichier et `.returns<T>()`.
export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY!,
  );
}
