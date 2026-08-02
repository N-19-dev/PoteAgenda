import { cn } from "@/lib/utils";

/** Groupe de lignes façon tableau d'affichage : un seul cadre, séparateurs hairline entre lignes. */
function ListRowGroup({ className, ...props }: React.ComponentProps<"ul">) {
  return (
    <ul
      className={cn("divide-y divide-border/60 overflow-hidden rounded-lg border border-border/60", className)}
      {...props}
    />
  );
}

function ListRow({ className, ...props }: React.ComponentProps<"li">) {
  return (
    <li
      className={cn(
        "relative flex items-center justify-between gap-2 bg-card px-3 py-2.5 transition-[background-color,padding-left] duration-200 before:absolute before:inset-y-0 before:left-0 before:w-0 before:bg-primary before:transition-[width] before:duration-200 hover:bg-muted/50 hover:pl-4 hover:before:w-0.5",
        className,
      )}
      {...props}
    />
  );
}

export { ListRowGroup, ListRow };
