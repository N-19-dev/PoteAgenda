import * as React from "react"

import { cn } from "@/lib/utils"

function EmptyState({
  icon,
  message,
  action,
  className,
}: {
  icon?: React.ReactNode
  message: React.ReactNode
  action?: React.ReactNode
  className?: string
}) {
  return (
    <div
      data-slot="empty-state"
      className={cn(
        "flex flex-col items-center gap-3 rounded-lg border border-dashed border-border bg-card py-14 text-center",
        className
      )}
    >
      {icon}
      <p className="text-sm text-muted-foreground">{message}</p>
      {action}
    </div>
  )
}

export { EmptyState }
