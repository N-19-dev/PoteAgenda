// Types métier écrits à la main à partir de supabase/migrations/0001_init.sql.
// À terme, remplacer par `supabase gen types typescript --linked` et
// réintroduire le generic <Database> sur les clients (client.ts / server.ts).
// Ces types ne sont volontairement PAS branchés en generic sur le client
// Supabase : la version actuelle de @supabase/supabase-js attend un schéma
// "Database" avec toute la métadonnée de relations (Relationships) issue du
// codegen officiel, qu'on ne peut pas reproduire fidèlement à la main sans
// faire dérailler l'inférence de `.from()/.rpc()/.insert()`. Le typage se
// fait donc au niveau applicatif via ces interfaces + `.returns<T>()`.

export type FriendshipStatus = "pending" | "accepted" | "declined" | "blocked";
export type GroupRole = "owner" | "member";

export interface Profile {
  id: string;
  username: string;
  email: string;
  avatar_url: string | null;
  created_at: string;
  updated_at: string;
}

export interface Friendship {
  id: string;
  requester_id: string;
  addressee_id: string;
  status: FriendshipStatus;
  created_at: string;
  updated_at: string;
}

export interface Group {
  id: string;
  name: string;
  description: string | null;
  owner_id: string;
  created_at: string;
  updated_at: string;
}

export interface GroupMember {
  group_id: string;
  user_id: string;
  role: GroupRole;
  joined_at: string;
}

export type CalendarEventSource = "manual" | "ics";
export type CalendarSourceKind = "file" | "url";

export interface CalendarEvent {
  id: string;
  user_id: string;
  title: string;
  start_at: string; // ISO timestamptz
  end_at: string;
  color: string;
  source: CalendarEventSource;
  source_id: string | null;
  external_uid: string | null;
  created_at: string;
  updated_at: string;
}

export interface CalendarSource {
  id: string;
  user_id: string;
  label: string;
  kind: CalendarSourceKind;
  ics_url: string | null;
  last_synced_at: string | null;
  created_at: string;
}

/** Retour de la RPC get_group_busy_events — jamais de titre ni de couleur. */
export interface BusyEvent {
  user_id: string;
  start_at: string;
  end_at: string;
}
