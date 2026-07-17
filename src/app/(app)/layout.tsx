import Link from "next/link";
import { redirect } from "next/navigation";
import { CalendarClock, Users, UsersRound } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { UserMenu } from "@/components/nav/user-menu";

const NAV_ITEMS = [
  { href: "/groups", label: "Groupes", icon: UsersRound },
  { href: "/agenda", label: "Mon agenda", icon: CalendarClock },
  { href: "/friends", label: "Amis", icon: Users },
];

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) redirect("/login");

  const { data: profile } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", user.id)
    .single();

  return (
    <div className="flex min-h-screen w-full flex-col">
      <header className="sticky top-0 z-30 flex items-center justify-between border-b border-border bg-background/95 px-4 py-3 backdrop-blur">
        <Link href="/groups" className="text-base font-semibold tracking-tight">
          PoteAgenda
        </Link>
        {profile && <UserMenu profile={profile} />}
      </header>

      <main className="flex-1 px-4 pb-24 pt-4">{children}</main>

      <nav className="fixed inset-x-0 bottom-0 z-30 mx-auto flex w-full max-w-md justify-around border-t border-border bg-background/95 py-2 backdrop-blur sm:max-w-2xl">
        {NAV_ITEMS.map(({ href, label, icon: Icon }) => (
          <Link
            key={href}
            href={href}
            className="flex flex-1 flex-col items-center gap-1 rounded-md py-1.5 text-[11px] text-muted-foreground transition-colors hover:text-foreground"
          >
            <Icon className="h-5 w-5" />
            {label}
          </Link>
        ))}
      </nav>
    </div>
  );
}
