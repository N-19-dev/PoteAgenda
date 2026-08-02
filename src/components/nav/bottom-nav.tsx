"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { CalendarClock, Mail, Users, UsersRound } from "lucide-react";
import { cn } from "@/lib/utils";

const NAV_ITEMS = [
  { href: "/agenda", label: "Mon agenda", icon: CalendarClock },
  { href: "/invitations", label: "Invitations", icon: Mail },
  { href: "/groups", label: "Groupes", icon: UsersRound },
  { href: "/friends", label: "Amis", icon: Users },
];

export function BottomNav() {
  const pathname = usePathname();

  return (
    <nav className="fixed inset-x-0 bottom-0 z-30 mx-auto flex w-full max-w-6xl justify-around border-t border-border bg-background/90 p-1 backdrop-blur-md sm:rounded-t-xl sm:border-x">
      {NAV_ITEMS.map(({ href, label, icon: Icon }) => {
        const active = pathname === href || pathname.startsWith(`${href}/`);
        return (
          <Link
            key={href}
            href={href}
            className={cn(
              "relative flex flex-1 flex-col items-center gap-1 rounded-lg py-2 text-[11px] font-medium transition-colors",
              active ? "text-primary" : "text-muted-foreground hover:text-foreground",
            )}
          >
            {active && <span className="absolute inset-0 -z-10 rounded-lg bg-accent" />}
            <span className="flex flex-col items-center gap-1">
              <Icon className="h-5 w-5" strokeWidth={active ? 2.4 : 2} />
              {label}
            </span>
          </Link>
        );
      })}
    </nav>
  );
}
