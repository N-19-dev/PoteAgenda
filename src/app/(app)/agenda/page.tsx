import { createClient } from "@/lib/supabase/server";
import { AgendaEditor } from "@/components/agenda/agenda-editor";
import { dateKey, parseDateParam, rangeForView, rangeLabel, type CalendarView } from "@/lib/schedule";
import type { BusyEvent, CalendarEvent, FriendshipStatus, OutingResponse, Profile } from "@/lib/supabase/types";

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
      p_range_start: dateKey(rangeStart),
      p_range_end: dateKey(rangeEnd),
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

  const myResponseByOuting = new Map(
    (participationRows ?? []).map((row) => [row.outing_id, row.response as OutingResponse]),
  );

  const { data: allParticipantRows } = outingIds.length > 0
    ? await supabase.from("outing_participants").select("outing_id, response").in("outing_id", outingIds)
    : { data: [] };
  const outingIdsAwaitingResponse = new Set(
    (allParticipantRows ?? []).filter((row) => row.response === "pending").map((row) => row.outing_id),
  );

  const outingsWithResponse = (outings ?? []).map((outing) => ({
    ...outing,
    myResponse: myResponseByOuting.get(outing.id) ?? "accepted",
    isConfirmed: outing.confirmed_at !== null || !outingIdsAwaitingResponse.has(outing.id),
  }));

  return (
    <div className="mx-auto max-w-6xl space-y-5">
      <div>
        <p className="text-sm font-medium text-primary">Agenda</p>
        <h1 className="mt-1 text-3xl font-semibold tracking-tight capitalize sm:text-4xl">
          {rangeLabel(view, date)}
        </h1>
        <p className="mt-2 text-sm text-muted-foreground">Touche un créneau libre pour ajouter une indisponibilité ou proposer une sortie à un ami.</p>
      </div>
      <AgendaEditor
        view={view}
        anchorDate={date}
        events={(events ?? []) as CalendarEvent[]}
        friends={friends}
        selectedFriendIds={selectedFriendIds}
        friendsBusyEvents={friendsBusyEvents}
        outings={outingsWithResponse}
        currentUserId={user!.id}
      />
    </div>
  );
}
