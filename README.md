# PoteAgenda

Trouve un créneau libre avec tes potes, sans exposer ton emploi du temps. Les
autres membres d'un groupe ne voient jamais le titre d'un événement — juste
« Occupé » ou « Libre ».

## Stack

- **Next.js 16** (App Router, TypeScript)
- **Tailwind CSS v4** + **shadcn/ui** (Base UI) + **Lucide React**
- **Supabase** (Auth + Postgres + RLS + RPC)

## Mise en route

### 1. Créer le projet Supabase

1. Crée un projet sur [supabase.com](https://supabase.com).
2. Dans **SQL Editor**, exécute dans l'ordre le contenu de chaque fichier de
   `supabase/migrations/` (`0001_init.sql`, `0002_...sql`, `0003_...sql`).
3. Récupère l'URL et la clé `publishable` du projet (**Project Settings → API Keys**).

### 2. Variables d'environnement

```bash
cp .env.local.example .env.local
```

Renseigne `NEXT_PUBLIC_SUPABASE_URL` et `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`.

### 3. Installer et lancer

```bash
npm install
npm run dev
```

Ouvre [http://localhost:3000](http://localhost:3000).

## Modèle de données & confidentialité

- `profiles` — profil public minimal (pseudo, email), créé automatiquement à
  l'inscription via un trigger sur `auth.users`.
- `friendships` — relations d'amitié avec flux demande/acceptation.
- `groups` / `group_members` — groupes et leurs membres.
- `calendar_events` — indisponibilités **datées** (titre, `start_at`/`end_at`
  en `timestamptz`, couleur), saisies à la main ou importées d'un calendrier
  externe. **Verrouillée par RLS : seul le propriétaire peut lire ses
  lignes.**
- `calendar_sources` — calendriers externes connectés (fichier `.ics` importé
  une fois, ou URL `.ics` resynchronisable à la demande). L'URL est aussi
  privée que le titre d'un événement (même garantie RLS).

Le partage de disponibilité entre membres d'un groupe passe uniquement par la
fonction RPC `get_group_busy_events(group_id, range_start, range_end)`
(`SECURITY DEFINER`), qui ne renvoie que `user_id`, `start_at`, `end_at` —
**jamais le titre ni la couleur**. C'est ce qui garantit que tes amis voient
« Occupé » et rien d'autre.

### Import de calendrier (.ics)

Depuis `/agenda/calendars`, on peut connecter un calendrier externe :

- **Fichier `.ics`** : import ponctuel (pas de resynchronisation possible,
  aucun fichier n'est conservé côté serveur).
- **URL `.ics`** (Google/Outlook/iCloud "adresse secrète") : récupérée
  côté serveur (route handler, jamais exposée au client), resynchronisable
  manuellement via le bouton dédié.

Le parsing utilise `node-ical` et expanse les événements récurrents (`RRULE`)
en occurrences concrètes sur un horizon glissant de 180 jours. Une
resynchronisation remplace transactionnellement (delete + insert, RPC
`resync_calendar_source`) toutes les occurrences importées d'une source.

## Structure

```
src/
  app/
    login/, signup/, auth/callback/   pages publiques
    (app)/                            layout authentifié + nav mobile
      groups/                         liste, vue Matcher, réglages
      agenda/                         agenda perso (semaine datée éditable)
        calendars/                    calendriers externes connectés (.ics)
      friends/                        amis, demandes, recherche
    api/calendar-sources/             route handlers d'import/resync .ics
  components/
    calendar/                         WeekGrid (grille datée) + WeekNav + MatcherGrid
    agenda/, friends/, groups/, nav/  UI par domaine
    ui/                               shadcn/ui
  lib/
    supabase/                         clients browser/server/middleware + types
    actions/                          Server Actions (groupes, amis, agenda, calendriers)
    schedule.ts                       constantes & calculs de créneaux (semaine datée)
    ics.ts                            parsing .ics (node-ical) + fetch serveur d'URL
supabase/
  migrations/                         schéma complet + RLS + RPC (0001, 0002, 0003)
```

## Notes techniques

- Les types Supabase (`src/lib/supabase/types.ts`) sont écrits à la main et
  volontairement **pas** branchés en generic sur les clients (`createClient`)
  — la version actuelle de `@supabase/supabase-js` attend la métadonnée de
  relations issue de `supabase gen types typescript --linked`, qu'on ne peut
  pas reproduire fidèlement sans un projet lié. Une fois le projet créé,
  génère les vrais types et réintroduis le generic `<Database>`.
- `src/proxy.ts` (convention Next.js 16, ex-`middleware.ts`) rafraîchit la
  session Supabase et protège les routes authentifiées.
