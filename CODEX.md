# Contexte Codex — PoteAgenda

Ce document complète `AGENTS.md`. Il donne le contexte durable du produit et
les garde-fous à conserver lors des prochaines évolutions. Le `README.md`
reste la documentation de mise en route destinée aux humains.

## Produit et promesse

PoteAgenda aide un groupe d'amis à trouver un créneau commun, sans révéler le
contenu de l'agenda de chacun. Le produit est en français et cible d'abord le
mobile : chaque utilisateur renseigne ou importe ses indisponibilités, puis
voit qui est libre dans un groupe.

La promesse de confidentialité est une contrainte fonctionnelle non
négociable : les autres utilisateurs ne doivent jamais pouvoir accéder au
titre, à la couleur, à l'URL ICS ou aux lignes brutes du calendrier d'autrui.
Ils ne voient que l'état « Occupé » / « Libre » et les intervalles associés.

## Stack et conventions importantes

- Next.js **16.2.10**, App Router, React 19, TypeScript, Tailwind CSS v4,
  shadcn/ui (Base UI), Framer Motion et Lucide.
- Supabase assure Auth et Postgres ; les migrations SQL sont dans
  `supabase/migrations/`.
- Les pages et layouts sont des Server Components par défaut. Limiter
  `"use client"` aux composants qui nécessitent état, événements ou API
  navigateur ; les mutations passent par les Server Actions dans
  `src/lib/actions/` ou par les Route Handlers nécessaires.
- Next 16 emploie `src/proxy.ts` (et non `middleware.ts`) pour la session et
  la protection des routes. Avant toute modification Next, lire le guide
  pertinent dans `node_modules/next/dist/docs/`, conformément à `AGENTS.md`.
- Les interfaces de `src/lib/supabase/types.ts` sont écrites à la main et les
  clients Supabase ne sont volontairement pas génériqués. Ne pas réintroduire
  `<Database>` sans types générés avec `supabase gen types`.

## Architecture fonctionnelle

- `/agenda` : calendrier personnel hebdomadaire daté. Ajout/suppression
  d'indisponibilités manuelles, et superposition optionnelle des créneaux
  occupés d'amis acceptés.
- `/agenda/calendars` : import d'un fichier `.ics` ou d'une URL ICS secrète ;
  les URL se resynchronisent à la demande. `src/lib/ics.ts` développe les
  récurrences sur 180 jours, avec limite de 5 Mo.
- `/groups` : création et liste des groupes ; `/groups/[groupId]` est la vue
  Matcher qui indique les disponibilités du groupe ; `settings` gère les
  membres.
- `/friends` : recherche de profils, demandes, acceptation et suppression
  d'amis.
- `src/components/calendar/week-grid.tsx` est la brique de calendrier
  réutilisée par l'agenda et le Matcher. `src/lib/schedule.ts` centralise les
  slots (30 min), les calculs de chevauchement et les semaines commençant le
  lundi.

## Données et sécurité

- Tables principales : `profiles`, `friendships`, `groups`, `group_members`,
  `calendar_events`, `calendar_sources`.
- Les politiques RLS de `calendar_events` et `calendar_sources` limitent les
  données brutes à leur propriétaire.
- Le partage passe exclusivement par les RPC `SECURITY DEFINER`
  `get_group_busy_events(group_id, range_start, range_end)` et
  `get_friends_busy_events(friend_ids, range_start, range_end)`. Elles ne
  retournent que `user_id`, `start_at`, `end_at`.
- La RPC `resync_calendar_source` remplace transactionnellement les événements
  d'une source ICS. Conserver sa vérification d'appartenance.
- Toute nouvelle lecture ou mutation côté serveur doit revérifier
  authentification et autorisation : une Server Action est appelable
  directement, pas seulement depuis son bouton.

## Direction visuelle actuelle

La refonte en cours adopte un outil de planning sombre, précis et calme :
fonds gris neutres, accent terracotta, Geist/Geist Mono, panneaux plans
bordés et interactions discrètes (révélations, balayage, grille avec
réticule). La navigation est mobile-first, avec barre basse fixe.

Pour toute tâche UI ou changement de direction artistique, appliquer les
consignes de `.claude/skills/front-elite/SKILL.md` : partir d'une intention
visuelle propre au produit, planifier la palette/typo/layout/signature avant
de coder, et respecter accessibilité, responsive et préférence de mouvement
réduit. Ne pas retomber dans un layout Tailwind générique.

## État du dépôt au 31 juillet 2026

La branche contient une refonte visuelle non commitée (CSS global, pages,
grilles, navigation, composants motion et composants UI). Elle doit être
traitée comme du travail utilisateur existant : l'inspecter et la préserver,
ne pas la réinitialiser ni la remplacer en bloc. La migration
`0004_friends_busy_events.sql` fait également partie de ce travail en cours.

Le dernier commit (`831045c`) a migré le modèle d'anciens créneaux
hebdomadaires récurrents vers des événements datés et l'import ICS. Les
migrations historiques `0001_init.sql` et `0003_calendar_events.sql` montrent
cette transition ; le schéma actuel est celui de `calendar_events` et non
celui d'`availabilities`.

## Vérifications habituelles

- `npm run lint` pour le contrôle statique.
- `npm run build` avant une livraison significative, si les variables
  Supabase nécessaires sont disponibles.
- Lors d'un changement de schéma, ajouter une migration additive et documenter
  l'ordre d'application ; ne pas modifier une migration déjà potentiellement
  appliquée.
