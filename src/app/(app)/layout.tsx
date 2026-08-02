import Link from "next/link";
import { redirect } from "next/navigation";
import { CalendarClock } from "lucide-react";
import { createClient } from "@/lib/supabase/server";
import { UserMenu } from "@/components/nav/user-menu";
import { BottomNav } from "@/components/nav/bottom-nav";

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
    <div className="flex min-h-screen w-full flex-col bg-secondary/60">
      <header className="sticky top-0 z-30 border-b border-border bg-background/80 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-4 py-3">
        <Link href="/agenda" className="flex items-center gap-2.5">
          <span className="flex h-7 w-7 items-center justify-center rounded-lg bg-primary text-primary-foreground">
            <CalendarClock className="h-4 w-4" />
          </span>
          <span className="text-lg font-semibold tracking-tight">PoteAgenda</span>
        </Link>
        {profile && <UserMenu profile={profile} />}
        </div>
      </header>

      <main className="flex-1 px-4 pb-24 pt-6">{children}</main>

      <BottomNav />
    </div>
  );
}
