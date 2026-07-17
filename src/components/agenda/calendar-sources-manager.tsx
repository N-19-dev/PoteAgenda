"use client";

import { useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { formatDistanceToNow } from "date-fns";
import { fr } from "date-fns/locale";
import { toast } from "sonner";
import { Plus, RefreshCw, Trash2 } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { deleteCalendarSource } from "@/lib/actions/calendar-sources";
import type { CalendarSource } from "@/lib/supabase/types";

export function CalendarSourcesManager({ sources }: { sources: CalendarSource[] }) {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const [tab, setTab] = useState<"file" | "url">("file");
  const [label, setLabel] = useState("");
  const [url, setUrl] = useState("");
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [isPending, startTransition] = useTransition();
  const [resyncingId, setResyncingId] = useState<string | null>(null);
  const [toDelete, setToDelete] = useState<CalendarSource | null>(null);

  function resetForm() {
    setLabel("");
    setUrl("");
    if (fileInputRef.current) fileInputRef.current.value = "";
  }

  function handleAdd(e: React.FormEvent) {
    e.preventDefault();
    startTransition(async () => {
      try {
        let res: Response;
        if (tab === "file") {
          const file = fileInputRef.current?.files?.[0];
          if (!file) {
            toast.error("Choisis un fichier .ics");
            return;
          }
          const formData = new FormData();
          formData.set("file", file);
          formData.set("label", label);
          res = await fetch("/api/calendar-sources", { method: "POST", body: formData });
        } else {
          if (!url.trim()) {
            toast.error("Renseigne une URL");
            return;
          }
          res = await fetch("/api/calendar-sources", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ label, ics_url: url.trim() }),
          });
        }
        if (!res.ok) {
          const body = await res.json().catch(() => null);
          toast.error(body?.error ?? "Import impossible");
          return;
        }
        const body = await res.json();
        toast.success(`Calendrier connecté (${body.imported} événement${body.imported > 1 ? "s" : ""})`);
        setOpen(false);
        resetForm();
        router.refresh();
      } catch {
        toast.error("Import impossible");
      }
    });
  }

  function handleResync(source: CalendarSource) {
    setResyncingId(source.id);
    startTransition(async () => {
      try {
        const res = await fetch(`/api/calendar-sources/${source.id}/resync`, { method: "POST" });
        if (!res.ok) {
          const body = await res.json().catch(() => null);
          toast.error(body?.error ?? "Resynchronisation impossible");
          return;
        }
        const body = await res.json();
        toast.success(`Recalé (${body.imported} événement${body.imported > 1 ? "s" : ""})`);
        router.refresh();
      } catch {
        toast.error("Resynchronisation impossible");
      } finally {
        setResyncingId(null);
      }
    });
  }

  function handleDelete() {
    if (!toDelete) return;
    startTransition(async () => {
      try {
        await deleteCalendarSource(toDelete.id);
        toast.success("Calendrier supprimé");
        setToDelete(null);
        router.refresh();
      } catch {
        toast.error("Suppression impossible");
      }
    });
  }

  return (
    <div className="space-y-3">
      <Dialog
        open={open}
        onOpenChange={(o) => {
          setOpen(o);
          if (!o) resetForm();
        }}
      >
        <DialogTrigger render={<Button size="sm" className="gap-1.5" />}>
          <Plus className="h-4 w-4" />
          Ajouter un calendrier
        </DialogTrigger>
        <DialogContent>
          <form onSubmit={handleAdd}>
            <DialogHeader>
              <DialogTitle>Connecter un calendrier</DialogTitle>
            </DialogHeader>
            <div className="space-y-4 py-4">
              <Tabs value={tab} onValueChange={(v) => setTab(v as "file" | "url")}>
                <TabsList className="w-full">
                  <TabsTrigger value="file" className="flex-1">
                    Fichier .ics
                  </TabsTrigger>
                  <TabsTrigger value="url" className="flex-1">
                    URL .ics
                  </TabsTrigger>
                </TabsList>
                <TabsContent value="file" className="space-y-3 pt-3">
                  <div className="space-y-1.5">
                    <Label htmlFor="ics-file">Fichier</Label>
                    <Input id="ics-file" type="file" accept=".ics,text/calendar" ref={fileInputRef} />
                  </div>
                </TabsContent>
                <TabsContent value="url" className="space-y-3 pt-3">
                  <div className="space-y-1.5">
                    <Label htmlFor="ics-url">URL</Label>
                    <Input
                      id="ics-url"
                      type="url"
                      placeholder="https://calendar.google.com/calendar/ical/.../basic.ics"
                      value={url}
                      onChange={(e) => setUrl(e.target.value)}
                    />
                  </div>
                </TabsContent>
              </Tabs>
              <div className="space-y-1.5">
                <Label htmlFor="ics-label">Nom (optionnel)</Label>
                <Input
                  id="ics-label"
                  placeholder="Mon agenda pro"
                  value={label}
                  onChange={(e) => setLabel(e.target.value)}
                />
              </div>
            </div>
            <DialogFooter>
              <Button type="submit" disabled={isPending}>
                {isPending ? "Import..." : "Importer"}
              </Button>
            </DialogFooter>
          </form>
        </DialogContent>
      </Dialog>

      {sources.length === 0 ? (
        <p className="text-sm text-muted-foreground">Aucun calendrier connecté pour l&apos;instant.</p>
      ) : (
        <ul className="space-y-2">
          {sources.map((source) => (
            <li
              key={source.id}
              className="flex items-center justify-between gap-2 rounded-lg border border-border p-3"
            >
              <div className="min-w-0 space-y-1">
                <div className="flex items-center gap-2">
                  <span className="truncate text-sm font-medium">{source.label}</span>
                  <Badge variant="outline">{source.kind === "file" ? "Fichier" : "URL"}</Badge>
                </div>
                <p className="text-[11px] text-muted-foreground">
                  {source.last_synced_at
                    ? `Synchronisé ${formatDistanceToNow(new Date(source.last_synced_at), {
                        addSuffix: true,
                        locale: fr,
                      })}`
                    : "Jamais synchronisé"}
                </p>
              </div>
              <div className="flex shrink-0 items-center gap-1.5">
                {source.kind === "url" && (
                  <Button
                    variant="outline"
                    size="icon"
                    disabled={isPending && resyncingId === source.id}
                    onClick={() => handleResync(source)}
                    aria-label="Resynchroniser"
                  >
                    <RefreshCw className={resyncingId === source.id ? "h-4 w-4 animate-spin" : "h-4 w-4"} />
                  </Button>
                )}
                <Button variant="outline" size="icon" onClick={() => setToDelete(source)} aria-label="Supprimer">
                  <Trash2 className="h-4 w-4" />
                </Button>
              </div>
            </li>
          ))}
        </ul>
      )}

      <Dialog open={!!toDelete} onOpenChange={(o) => !o && setToDelete(null)}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Supprimer « {toDelete?.label} » ?</DialogTitle>
          </DialogHeader>
          <p className="text-sm text-muted-foreground">
            Les événements importés depuis ce calendrier seront aussi supprimés.
          </p>
          <DialogFooter>
            <Button variant="outline" onClick={() => setToDelete(null)}>
              Annuler
            </Button>
            <Button variant="destructive" disabled={isPending} onClick={handleDelete}>
              Supprimer
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
