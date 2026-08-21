-- Permet de connecter un calendrier natif iOS (EventKit) comme source
-- importée, au même titre qu'un fichier ou une URL .ics. Le parsing/mapping
-- des événements EventKit reste fait côté client (app Swift, comme le
-- fait le route handler Next.js pour l'ICS) ; seul le résultat déjà résolu
-- (title/start_at/end_at/external_uid) est envoyé à resync_calendar_source.
--
-- device_calendar_id stocke l'EKCalendar.calendarIdentifier local à
-- l'appareil qui a connecté la source : il n'a de sens que pour retrouver
-- ce calendrier lors d'une resynchronisation depuis ce même appareil.

alter table public.calendar_sources
  drop constraint if exists calendar_sources_kind_check;

alter table public.calendar_sources
  add constraint calendar_sources_kind_check check (kind in ('file', 'url', 'device'));

alter table public.calendar_sources
  add column if not exists device_calendar_id text;

alter table public.calendar_sources
  drop constraint if exists device_id_requires_device_kind;

alter table public.calendar_sources
  add constraint device_id_requires_device_kind check (kind <> 'device' or device_calendar_id is not null);

comment on column public.calendar_sources.device_calendar_id is
  'EKCalendar.calendarIdentifier local à l''appareil, pour les sources kind=device (connexion EventKit iOS). Sans signification côté serveur au-delà du bookkeeping.';
