import { createClient } from "@/lib/supabase/server";
import { InvitationList, type InvitationItem } from "@/components/outings/invitation-list";
import type { Outing, OutingParticipant, Profile } from "@/lib/supabase/types";

export default async function InvitationsPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  const { data: rows } = await supabase.from("outing_participants").select("outing_id").eq("user_id", user!.id);
  const ids = (rows ?? []).map((row) => row.outing_id);
  const { data: outings } = ids.length ? await supabase.from("outings").select("*").in("id", ids).order("starts_at") : { data: [] };
  const { data: participantRows } = ids.length ? await supabase.from("outing_participants").select("*, profile:profiles(*)").in("outing_id", ids) : { data: [] };
  const invitations: InvitationItem[] = ((outings ?? []) as Outing[]).map((outing) => ({ outing, participants: (participantRows ?? []).filter((row) => row.outing_id === outing.id) as (OutingParticipant & { profile: Profile })[] }));
  return <div className="mx-auto max-w-2xl space-y-5"><div><p className="text-sm font-medium text-primary">À décider</p><h1 className="mt-1 text-3xl font-semibold tracking-tight">Invitations</h1><p className="mt-2 text-sm text-muted-foreground">Réponds aux sorties proposées par tes amis.</p></div><InvitationList invitations={invitations} currentUserId={user!.id} /></div>;
}
