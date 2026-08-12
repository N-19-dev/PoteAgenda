"use client";

import { useEffect, useMemo, useRef, useState, useTransition } from "react";
import { format } from "date-fns";
import { fr } from "date-fns/locale";
import { Send } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { getOutingMessages, sendOutingMessage, type OutingMessageWithProfile } from "@/lib/actions/outings";
import { cn } from "@/lib/utils";

export type OutingParticipantOption = { id: string; username: string };

function renderMentions(body: string, participants: OutingParticipantOption[]) {
  if (participants.length === 0) return body;
  const usernames = [...new Set(participants.map((p) => p.username))]
    .sort((a, b) => b.length - a.length)
    .map((username) => username.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
  if (usernames.length === 0) return body;
  const pattern = new RegExp(`@(${usernames.join("|")})\\b`, "g");
  const parts: React.ReactNode[] = [];
  let lastIndex = 0;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(body))) {
    if (match.index > lastIndex) parts.push(body.slice(lastIndex, match.index));
    parts.push(
      <span key={match.index} className="font-semibold text-primary">
        {match[0]}
      </span>,
    );
    lastIndex = match.index + match[0].length;
  }
  parts.push(body.slice(lastIndex));
  return parts;
}

export function OutingMessages({
  outingId,
  currentUserId,
  participants,
}: {
  outingId: string;
  currentUserId: string;
  participants: OutingParticipantOption[];
}) {
  const [messages, setMessages] = useState<OutingMessageWithProfile[] | null>(null);
  const [body, setBody] = useState("");
  const [mentionedIds, setMentionedIds] = useState<Set<string>>(new Set());
  const [isPending, startTransition] = useTransition();
  const scrollRef = useRef<HTMLDivElement>(null);

  const taggableParticipants = useMemo(
    () => participants.filter((p) => p.id !== currentUserId),
    [participants, currentUserId],
  );

  useEffect(() => {
    let cancelled = false;
    getOutingMessages(outingId)
      .then((data) => { if (!cancelled) setMessages(data); })
      .catch(() => { if (!cancelled) setMessages([]); });
    return () => { cancelled = true; };
  }, [outingId]);

  useEffect(() => {
    if (!messages || !scrollRef.current) return;
    scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
  }, [messages]);

  const trailingMentionQuery = /(?:^|\s)@([a-zA-Z0-9_.-]*)$/.exec(body)?.[1] ?? null;
  const suggestions = trailingMentionQuery !== null
    ? taggableParticipants
        .filter((p) => p.username.toLowerCase().startsWith(trailingMentionQuery.toLowerCase()))
        .slice(0, 5)
    : [];

  function selectMention(participant: OutingParticipantOption) {
    setBody((current) => current.replace(/@([a-zA-Z0-9_.-]*)$/, `@${participant.username} `));
    setMentionedIds((ids) => new Set(ids).add(participant.id));
  }

  function submit(event: React.FormEvent) {
    event.preventDefault();
    const trimmed = body.trim();
    if (!trimmed) return;
    startTransition(async () => {
      try {
        await sendOutingMessage(outingId, trimmed, [...mentionedIds]);
        setBody("");
        setMentionedIds(new Set());
        setMessages(await getOutingMessages(outingId));
      } catch (error) {
        toast.error(error instanceof Error ? error.message : "Impossible d'envoyer le message");
      }
    });
  }

  return (
    <div className="mt-3 space-y-2 rounded-lg border border-border/60 bg-muted/30 p-3">
      <div ref={scrollRef} className="max-h-56 space-y-2 overflow-y-auto pr-1">
        {messages === null && <p className="text-xs text-muted-foreground">Chargement…</p>}
        {messages !== null && messages.length === 0 && (
          <p className="text-xs text-muted-foreground">Aucun message pour l&apos;instant — lance la discussion.</p>
        )}
        {messages?.map((message) => {
          const mine = message.sender_id === currentUserId;
          return (
            <div key={message.id} className={cn("flex flex-col", mine ? "items-end" : "items-start")}>
              <div
                className={cn(
                  "max-w-[85%] rounded-lg px-3 py-1.5 text-sm",
                  mine ? "bg-primary text-primary-foreground" : "border border-border bg-background",
                )}
              >
                {!mine && <p className="text-[11px] font-medium text-muted-foreground">{message.profile.username}</p>}
                <p className="whitespace-pre-wrap break-words">{renderMentions(message.body, participants)}</p>
              </div>
              <span className="mt-0.5 text-[10px] text-muted-foreground">
                {format(new Date(message.created_at), "d MMM HH:mm", { locale: fr })}
              </span>
            </div>
          );
        })}
      </div>
      <form onSubmit={submit} className="relative space-y-1.5">
        {suggestions.length > 0 && (
          <div className="flex flex-wrap gap-1.5">
            {suggestions.map((participant) => (
              <button
                key={participant.id}
                type="button"
                onClick={() => selectMention(participant)}
                className="rounded-full border border-primary/40 bg-primary/5 px-2.5 py-1 text-xs font-medium text-primary hover:bg-primary/10"
              >
                @{participant.username}
              </button>
            ))}
          </div>
        )}
        <div className="flex items-center gap-2">
          <input
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="Écrire un message… (@ pour taguer)"
            maxLength={2000}
            aria-label="Message"
            className="h-9 flex-1 rounded-lg border border-input bg-background px-3 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
          />
          <Button type="submit" size="icon" disabled={isPending || !body.trim()} aria-label="Envoyer">
            <Send className="size-4" />
          </Button>
        </div>
      </form>
    </div>
  );
}
