import Link from "next/link";
import { ChevronRight, UsersRound } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { CreateGroupDialog } from "@/components/groups/create-group-dialog";
import type { Group } from "@/lib/supabase/types";

export default async function GroupsPage() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: memberships } = await supabase
    .from("group_members")
    .select("groups:groups(*)")
    .eq("user_id", user!.id)
    .returns<{ groups: Group }[]>();

  const groups = (memberships ?? []).map((m) => m.groups).filter(Boolean);

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-semibold tracking-tight">Mes groupes</h1>
        <CreateGroupDialog />
      </div>

      {groups.length === 0 ? (
        <div className="flex flex-col items-center gap-2 rounded-lg border border-dashed border-border py-14 text-center">
          <UsersRound className="h-8 w-8 text-muted-foreground" />
          <p className="text-sm text-muted-foreground">
            Crée un premier groupe pour trouver un créneau avec tes potes.
          </p>
        </div>
      ) : (
        <ul className="space-y-2">
          {groups.map((group) => (
            <li key={group.id}>
              <Link
                href={`/groups/${group.id}`}
                className="flex items-center justify-between rounded-lg border border-border bg-card px-4 py-3.5 transition-colors hover:bg-accent/50"
              >
                <div>
                  <p className="font-medium">{group.name}</p>
                  {group.description && (
                    <p className="line-clamp-1 text-xs text-muted-foreground">
                      {group.description}
                    </p>
                  )}
                </div>
                <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
