# PoteAgenda

Trouve un créneau libre avec tes potes, sans exposer ton emploi du temps. Les
autres membres d'un groupe ne voient jamais le titre d'un événement — juste
« Occupé » ou « Libre ».

Ce dépôt contient l'application iOS native (SwiftUI) et le backend Supabase
qu'elle utilise.

## Stack

- **SwiftUI** (iOS natif) — voir `ios/PoteAgenda/`
- **Supabase** (Auth + Postgres + RLS + RPC)
- **EventKit** pour l'import des calendriers natifs de l'appareil

## Mise en route

### 1. Créer le projet Supabase

1. Crée un projet sur [supabase.com](https://supabase.com).
2. Dans **SQL Editor**, exécute dans l'ordre le contenu de chaque fichier de
   `supabase/migrations/`.
3. Récupère l'URL et la clé `publishable` du projet (**Project Settings → API Keys**).

### 2. Lancer l'app iOS

Voir `ios/PoteAgenda/README.md` pour la configuration de `Supabase.plist` et
le lancement dans Xcode.

## Développer / tester en local (backend Supabase)

Nécessite [Docker](https://docs.docker.com/get-docker/) et le CLI Supabase
(`npx supabase` fonctionne sans installation globale) :

```bash
supabase start        # démarre Postgres + Auth + REST + Studio en local (Docker)
supabase db reset      # recrée la base, applique supabase/migrations/ puis supabase/seed.sql
supabase test db --local   # lance les tests pgTAP (supabase/tests/database/)
supabase stop           # arrête le stack local
```

`supabase status` affiche les URLs locales (API, Studio sur
`http://127.0.0.1:54323`, etc.) et les clés de dev. `supabase/seed.sql` est
local uniquement (jamais poussé en prod) : il accorde les privilèges que la
plateforme Supabase hébergée accorde automatiquement en dehors des
migrations, pour que le comportement local corresponde à la prod — voir
`docs/2026-08-21-security-review.md` pour le détail.

## Modèle de données & confidentialité

- `profiles` — profil public minimal (pseudo, email), créé automatiquement à
  l'inscription via un trigger sur `auth.users`.
- `friendships` — relations d'amitié avec flux demande/acceptation.
- `groups` / `group_members` — groupes et leurs membres.
- `calendar_events` — indisponibilités **datées** (titre, `start_at`/`end_at`
  en `timestamptz`, couleur), saisies à la main ou importées. **Verrouillée
  par RLS : seul le propriétaire peut lire ses lignes.**
- `calendar_sources` — calendriers externes connectés. Aussi privés que le
  titre d'un événement (même garantie RLS).

Le partage de disponibilité entre membres d'un groupe passe uniquement par les
fonctions RPC `SECURITY DEFINER` `get_group_busy_events(group_id, range_start, range_end)`
et `get_friends_busy_events(friend_ids, range_start, range_end)`, qui ne
renvoient que `user_id`, `start_at`, `end_at` — **jamais le titre ni la
couleur**. C'est ce qui garantit que tes amis voient « Occupé » et rien
d'autre.

## Structure

```
ios/
  PoteAgenda/                Projet Xcode (SwiftUI)
    PoteAgenda/
      Views/                 Écrans (agenda, groupes, amis, invitations…)
      ViewModels/             SessionStore, AppDataStore
      Services/               SupabaseService, EventKitService, DateHelpers
      Models/                 Modèles de données
      Resources/              Supabase.plist (config, non commité)
supabase/
  migrations/                 schéma complet + RLS + RPC
  tests/database/              tests pgTAP (RLS, RPC, non-régression)
  seed.sql                     grants de dev local uniquement (jamais poussé en prod)
docs/
  2026-08-21-security-review.md  revue de sécurité + corrections + comment tester
```

## Historique des revues

- [`docs/2026-08-21-security-review.md`](docs/2026-08-21-security-review.md) —
  revue de sécurité complète (failles d'autorisation RLS, fuite d'erreurs
  backend, collecte calendrier, rétention des messages, Keychain,
  notifications, validation des mentions) + tests de non-régression ajoutés.
