# Contexte projet — PoteAgenda (iOS)

PoteAgenda aide un groupe d'amis à trouver un créneau commun, sans révéler le
contenu de l'agenda de chacun. Chaque utilisateur renseigne ses
indisponibilités, puis voit qui est libre dans un groupe. Les autres membres
ne voient jamais le titre, la couleur ou les détails d'un événement — juste
« Occupé » / « Libre » et les intervalles associés. C'est une contrainte
fonctionnelle non négociable.

Le dépôt ne contient plus que l'application iOS native (`ios/PoteAgenda/`) et
le backend Supabase (`supabase/migrations/`) qu'elle consomme directement. Il
n'y a plus d'application web.

## Stack

- SwiftUI natif, cible iOS. Projet Xcode dans `ios/PoteAgenda/PoteAgenda.xcodeproj`.
- Supabase (Auth + Postgres + RLS + RPC) via `SupabaseService.swift` /
  `SupabaseConfig.swift`, configuré par `ios/PoteAgenda/PoteAgenda/Resources/Supabase.plist`
  (dupliqué depuis `Supabase.example.plist`, non commité).
- EventKit pour l'accès aux calendriers natifs de l'appareil
  (`EventKitService.swift`).
- Les migrations SQL du schéma, RLS et RPC sont dans `supabase/migrations/` ;
  appliquer un fichier additif pour tout changement de schéma, ne jamais
  modifier une migration déjà potentiellement appliquée.

## Sécurité et confidentialité

- Le partage de disponibilité passe exclusivement par les RPC
  `SECURITY DEFINER` `get_group_busy_events` et `get_friends_busy_events`, qui
  ne renvoient que `user_id`, `start_at`, `end_at`.
- Les politiques RLS limitent les données brutes de calendrier à leur
  propriétaire ; toute nouvelle requête doit préserver cette isolation.

Voir `ios/PoteAgenda/README.md` pour la configuration et l'état du portage.
