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
    <div className="mx-auto max-w-3xl space-y-5">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <p className="text-sm font-medium text-primary">{groups.length} groupe{groups.length > 1 ? "s" : ""}</p>
          <h1 className="mt-1 text-3xl font-semibold tracking-tight">Groupes</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Invite un groupe complet à une sortie et suis les réponses de chacun.
          </p>
        </div>
        {groups.length > 0 && <CreateGroupDialog />}
      </div>

      {groups.length === 0 ? (
        <div className="flex flex-col items-center gap-3 rounded-lg border border-dashed border-border bg-card py-14 text-center">
          <UsersRound className="h-8 w-8 text-muted-foreground" />
          <p className="text-sm text-muted-foreground">
            Crée un premier groupe pour trouver un créneau avec tes potes.
          </p>
          <CreateGroupDialog />
        </div>
      ) : (
        <ul className="grid grid-cols-1 gap-2.5 sm:grid-cols-2">
          {groups.map((group) => (
            <li key={group.id}>
              <Link
                href={`/groups/${group.id}`}
                className="group flex items-center justify-between rounded-lg border border-border bg-card px-4 py-3.5 shadow-sm transition-colors hover:border-primary/40"
              >
                <div>
                  <p className="font-medium">{group.name}</p>
                  {group.description && (
                    <p className="line-clamp-1 text-xs text-muted-foreground">
                      {group.description}
                    </p>
                  )}
                </div>
                <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground transition-transform group-hover:translate-x-0.5" />
              </Link>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
