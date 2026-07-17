import Link from "next/link";
import { notFound } from "next/navigation";
import { addDays } from "date-fns";
import { ArrowLeft, Settings } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { MatcherGrid } from "@/components/calendar/matcher-grid";
import { dateKey, parseWeekParam } from "@/lib/schedule";
import type { BusyEvent, Profile } from "@/lib/supabase/types";

interface PageProps {
  params: Promise<{ groupId: string }>;
  searchParams: Promise<{ week?: string }>;
}

export default async function GroupMatcherPage({ params, searchParams }: PageProps) {
  const { groupId } = await params;
  const { week } = await searchParams;
  const weekStart = parseWeekParam(week);
  const weekEnd = addDays(weekStart, 7);
  const supabase = await createClient();

  const { data: group } = await supabase
    .from("groups")
    .select("*")
    .eq("id", groupId)
    .single();

  if (!group) notFound();

  const { data: memberRows } = await supabase
    .from("group_members")
    .select("user_id, role, profiles:profiles(*)")
    .eq("group_id", groupId)
    .returns<{ user_id: string; role: string; profiles: Profile }[]>();

  const members: Profile[] = (memberRows ?? []).map((row) => row.profiles).filter(Boolean);

  const { data: busyEvents, error: busyError } = await supabase.rpc("get_group_busy_events", {
    p_group_id: groupId,
    p_range_start: dateKey(weekStart),
    p_range_end: dateKey(weekEnd),
  });

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between gap-2">
        <Link
          href="/groups"
          className="flex items-center gap-1 text-sm text-muted-foreground hover:text-foreground"
        >
          <ArrowLeft className="h-4 w-4" />
          Groupes
        </Link>
        <Link href={`/groups/${groupId}/settings`}>
          <Button variant="ghost" size="icon" aria-label="Réglages du groupe">
            <Settings className="h-4 w-4" />
          </Button>
        </Link>
      </div>

      <div>
        <h1 className="text-xl font-semibold tracking-tight">{group.name}</h1>
        {group.description && (
          <p className="text-sm text-muted-foreground">{group.description}</p>
        )}
      </div>

      <div className="flex items-center gap-2">
        <div className="flex -space-x-2">
          {members.map((m) => (
            <Avatar key={m.id} className="h-7 w-7 border-2 border-background">
              <AvatarFallback className="text-[10px]">
                {m.username.slice(0, 2).toUpperCase()}
              </AvatarFallback>
            </Avatar>
          ))}
        </div>
        <span className="text-xs text-muted-foreground">
          {members.length} membre{members.length > 1 ? "s" : ""}
        </span>
      </div>

      {busyError ? (
        <p className="rounded-md border border-destructive/40 bg-destructive/10 p-3 text-sm text-destructive">
          Impossible de charger les disponibilités du groupe.
        </p>
      ) : (
        <MatcherGrid
          weekStart={weekStart}
          members={members}
          busyEvents={(busyEvents ?? []) as BusyEvent[]}
        />
      )}
    </div>
  );
}
