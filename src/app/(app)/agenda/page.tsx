import { createClient } from "@/lib/supabase/server";
import { AgendaEditor } from "@/components/agenda/agenda-editor";
import { parseDateParam, rangeForView, type CalendarView } from "@/lib/schedule";
import type { BusyEvent, CalendarEvent, FriendshipStatus, Outing, Profile } from "@/lib/supabase/types";

interface PageProps {
  searchParams: Promise<{ view?: string; date?: string; friends?: string }>;
}

interface FriendshipRow {
  id: string;
  status: FriendshipStatus;
  requester_id: string;
  addressee_id: string;
  requester: Profile;
  addressee: Profile;
}

const VALID_VIEWS: CalendarView[] = ["day", "week", "month"];

export default async function AgendaPage({ searchParams }: PageProps) {
  const { view: viewParam, date: dateParam, friends: friendsParam } = await searchParams;
  const view: CalendarView = VALID_VIEWS.includes(viewParam as CalendarView) ? (viewParam as CalendarView) : "week";
  const date = parseDateParam(dateParam);
  const { start: rangeStart, end: rangeEnd } = rangeForView(view, date);

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: events } = await supabase
    .from("calendar_events")
    .select("*")
    .eq("user_id", user!.id)
    .lt("start_at", rangeEnd.toISOString())
    .gt("end_at", rangeStart.toISOString())
    .order("start_at");

  const { data: friendshipRows } = await supabase
    .from("friendships")
    .select(
      "id, status, requester_id, addressee_id, requester:profiles!friendships_requester_id_fkey(*), addressee:profiles!friendships_addressee_id_fkey(*)",
    )
    .or(`requester_id.eq.${user!.id},addressee_id.eq.${user!.id}`)
    .eq("status", "accepted")
    .returns<FriendshipRow[]>();

  const friends: Profile[] = (friendshipRows ?? []).map((r) =>
    r.requester_id === user!.id ? r.addressee : r.requester,
  );

  const selectedFriendIds = (friendsParam ?? "")
    .split(",")
    .map((id) => id.trim())
    .filter((id) => friends.some((f) => f.id === id));

  let friendsBusyEvents: BusyEvent[] = [];
  if (selectedFriendIds.length > 0) {
    const { data } = await supabase.rpc("get_friends_busy_events", {
      p_friend_ids: selectedFriendIds,
      p_range_start: rangeStart.toISOString().slice(0, 10),
      p_range_end: rangeEnd.toISOString().slice(0, 10),
    });
    friendsBusyEvents = (data ?? []) as BusyEvent[];
  }

  const { data: participationRows } = await supabase
    .from("outing_participants")
    .select("outing_id, response")
    .eq("user_id", user!.id);
  const outingIds = (participationRows ?? [])
    .filter((row) => row.response !== "declined")
    .map((row) => row.outing_id);
  const { data: outings } = outingIds.length > 0
    ? await supabase.from("outings").select("*").in("id", outingIds)
      .lt("starts_at", rangeEnd.toISOString()).gt("ends_at", rangeStart.toISOString())
    : { data: [] };

  return (
    <div className="mx-auto max-w-6xl space-y-5">
      <div>
        <p className="text-sm font-medium text-primary">Mon planning</p>
        <h1 className="mt-1 text-3xl font-semibold tracking-tight sm:text-4xl">Agenda</h1>
        <p className="mt-2 text-sm text-muted-foreground">Touche un créneau libre pour ajouter une indisponibilité ou proposer une sortie à un ami.</p>
      </div>
      <AgendaEditor
        view={view}
        anchorDate={date}
        events={(events ?? []) as CalendarEvent[]}
        friends={friends}
        selectedFriendIds={selectedFriendIds}
        friendsBusyEvents={friendsBusyEvents}
        outings={(outings ?? []) as Outing[]}
      />
    </div>
  );
}
