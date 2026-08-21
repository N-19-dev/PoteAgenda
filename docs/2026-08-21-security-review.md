# Revue de sécurité — 2026-08-21

Revue de sécurité complète de PoteAgenda (iOS + Supabase), suivie de la
correction de tous les points P1/P2/P3 identifiés et de l'ajout de tests de
non-régression. Ce document résume ce qui a été trouvé, ce qui a été corrigé,
et comment vérifier que ça fonctionne toujours.

## P1 — failles d'autorisation (critiques)

Toutes corrigées dans **`supabase/migrations/0018_fix_authz_holes.sql`**.

1. **Auto-ajout à n'importe quel groupe.** La policy
   `group_members_insert_owner` acceptait `user_id = auth.uid()` comme
   condition indépendante : n'importe quel utilisateur connaissant un
   `group_id` pouvait s'y ajouter lui-même, sans être owner.
   → Policy corrigée : seul le owner du groupe peut insérer des membres (y
   compris s'insérer lui-même à la création, puisqu'il est owner à ce
   moment-là).

2. **Auto-acceptation d'une demande d'ami.** `friendships_update_involved`
   autorisait `auth.uid() in (requester_id, addressee_id)` à la fois pour
   voir la ligne et pour la modifier : le demandeur pouvait passer lui-même
   le statut à `accepted`.
   → Nouvelle policy `friendships_update_addressee_responds` : seul le
   destinataire peut répondre.

3. **Détournement d'une ligne `outing_participants` vers une autre sortie.**
   La policy update ne figeait ni `outing_id` ni `user_id` : un participant
   pouvait PATCH sa ligne pour la faire pointer vers une sortie à laquelle il
   n'avait jamais été invité, devenant ainsi "participant" (donc lecteur) de
   son contenu.
   → Trigger `outing_participants_lock_identity` : bloque tout changement de
   `outing_id`/`user_id` sur une ligne existante, quelle que soit la policy
   RLS utilisée pour l'UPDATE.

## P2 — corrections

- **Erreurs Supabase brutes affichées en clair dans l'UI**
  (`SupabaseService.swift`) : les messages utilisateur sont maintenant
  génériques par catégorie de statut HTTP (401/403, 404, 409, 429, 5xx). Le
  détail brut (code Postgres/PostgREST, texte SQL) n'est loggé qu'en
  `#if DEBUG`, jamais montré à l'utilisateur.

- **Import calendrier sur-collectait titres + 180 jours**
  (`EventKitService.swift`, `SettingsView.swift`) :
  - Horizon réduit à 90 jours.
  - Nouveau toggle **"Importer le vrai titre de mes événements"**, désactivé
    par défaut : sans ça, seul `"Occupé"` part vers Supabase.
  - Résumé de confirmation (nombre d'événements, horizon, avec/sans titre)
    avant la première synchronisation d'un calendrier.

- **Rétention des messages de sortie = masquage, pas suppression**
  (`supabase/migrations/0019_purge_expired_outing_messages.sql`) : les
  messages expirés étaient seulement filtrés par RLS, jamais supprimés.
  Ajout d'une fonction `purge_expired_outing_messages()` + `pg_cron`
  quotidien (03h00) qui les supprime réellement. **Nécessite l'extension
  `pg_cron` activée sur le projet Supabase** (Database → Extensions dans le
  dashboard) ; si elle n'est pas dispo sur le plan, la migration échoue à
  `create extension` et il faut soit l'activer, soit déclencher la purge
  autrement (Edge Function planifiée) en attendant.

- **Refresh token Keychain trop permissif** (`KeychainService.swift`) :
  accessibilité passée de `AfterFirstUnlock` à
  `AfterFirstUnlockThisDeviceOnly` — la session ne peut plus migrer vers un
  autre appareil via une restauration de sauvegarde chiffrée.

## P3 — corrections

- **Notifications locales exposaient du contenu sensible sur écran
  verrouillé** (`AppDataStore.swift`, `SettingsView.swift`) : nouveau toggle
  **"Masquer le contenu des notifications"**, activé par défaut. Invitation,
  relance, mention et rappel de départ affichent un texte générique quand
  actif ("Ouvre PoteAgenda pour voir les détails.").

- **`mentioned_user_ids` non validés côté serveur**
  (`supabase/migrations/0020_validate_outing_message_mentions.sql`) :
  trigger qui rejette tout message mentionnant un utilisateur qui n'est ni
  participant ni créateur de la sortie. Ne rétro-purge pas les résidus
  historiques après suppression de compte (sans conséquence : aucune policy
  ne s'appuie sur cette colonne pour l'autorisation, cf. commentaire de
  `0014_delete_own_account.sql`).

## Bug trouvé pendant l'écriture des tests (et corrigé)

En testant `purge_expired_outing_messages()`, découverte que Postgres
accorde `EXECUTE` à `PUBLIC` par défaut à la création d'une fonction : sans
`revoke` explicite, **n'importe quel utilisateur authentifié aurait pu
déclencher la purge à volonté** via l'endpoint RPC PostgREST
(`/rest/v1/rpc/purge_expired_outing_messages`), alors que seul `pg_cron`
devait pouvoir l'appeler. Ajout d'un `revoke execute ... from public` dans
la même migration `0019`. Risque réel très faible (la fonction ne fait que
supprimer des lignes déjà objectivement expirées, sans dépendre de l'appelant
ni exposer de données), mais corrigé quand même par cohérence avec le design
documenté.

## Tests de non-régression ajoutés

### SQL / RLS / RPC (pgTAP)

`supabase/tests/database/` — 6 fichiers de test + 1 fichier d'aide
(`00_helpers.sql`, crée un schéma `tests` avec des fonctions pour simuler
un utilisateur authentifié sans dépendre de PostgREST). Couvre les 3 P1, la
confidentialité des titres (`get_friends_busy_events`), la rétention/purge
des messages, et la validation des mentions.

`supabase/seed.sql` — **local uniquement**, jamais poussé en prod par
`supabase db push`. La plateforme Supabase hébergée accorde automatiquement
les privilèges CRUD de base sur les tables `public` à `anon`/`authenticated`
(hors migrations utilisateur) ; le CLI local ne reproduit pas ce
comportement. Ce fichier ajoute l'équivalent pour que les tests locaux
correspondent à la prod. Volontairement **pas** de grant équivalent sur les
fonctions : chaque RPC gère son propre `grant execute` explicite dans sa
migration (voir le bug ci-dessus, précisément ce que ce choix protège).

**Lancer les tests localement :**

```bash
cd /Users/nathansornet/Documents/PoteAgenda
supabase db reset --local   # recrée la base, applique migrations + seed.sql
supabase test db --local    # lance les 6 fichiers pgTAP (24 assertions)
supabase stop                # arrête le stack Docker local
```

Nécessite Docker (le CLI local tourne dans des conteneurs). `npx supabase`
fonctionne aussi si le CLI n'est pas installé globalement.

### iOS (XCTest)

- `PoteAgendaTests/KeychainServiceTests.swift` — vérifie l'accessibilité
  Keychain (`AfterFirstUnlockThisDeviceOnly`) et le round-trip save/load/delete.
- `PoteAgendaTests/SupabaseServiceErrorMappingTests.swift` — vérifie que les
  messages d'erreur génériques ne contiennent jamais de vocabulaire backend
  (nom de contrainte SQL, code SQLSTATE, etc.).

Ajoutés au target `PoteAgendaTests` dans `PoteAgenda.xcodeproj`. **Non
exécutés lors de cette session** (pas de Xcode complet disponible, seulement
les Command Line Tools) — à lancer une fois dans Xcode avant de merger, voir
`ios/PoteAgenda/README.md`.

### CI

- `.github/workflows/db-tests.yml` — relance la suite pgTAP sur chaque PR
  touchant `supabase/`.
- `.github/workflows/secret-scan.yml` + `.gitleaks.toml` — scan gitleaks à
  chaque push/PR, avec une règle custom pour les tokens `sbp_...` (le format
  du token Supabase). Testé localement contre le vrai `.env.local` : détecte
  bien le token, la clé publishable et le mot de passe DB.

## Reste à faire (pas automatisable par moi)

**Rotation du token Supabase (`sbp_...`) et du mot de passe DB dans
`.env.local`.** Ce fichier n'a jamais été commité (vérifié dans tout
l'historique git), mais son contenu a été affiché plusieurs fois dans les
sessions Claude qui ont mené cette revue. Rotation à faire depuis le
dashboard Supabase :
- Token d'accès : *Account → Access Tokens*
- Mot de passe DB : *Project Settings → Database*

Après rotation, mettre à jour `.env.local` avec les nouvelles valeurs.

## Fichiers créés/modifiés dans cette revue

```
supabase/migrations/0018_fix_authz_holes.sql                (nouveau)
supabase/migrations/0019_purge_expired_outing_messages.sql  (nouveau)
supabase/migrations/0020_validate_outing_message_mentions.sql (nouveau)
supabase/config.toml                                        (nouveau, supabase init)
supabase/seed.sql                                            (nouveau)
supabase/tests/database/*.sql                                (nouveau, 7 fichiers)
.github/workflows/db-tests.yml                                (nouveau)
.github/workflows/secret-scan.yml                             (nouveau)
.gitleaks.toml                                                (nouveau)
ios/.../Services/KeychainService.swift                        (modifié)
ios/.../Services/SupabaseService.swift                        (modifié)
ios/.../Services/EventKitService.swift                        (modifié)
ios/.../ViewModels/AppDataStore.swift                          (modifié)
ios/.../Views/SettingsView.swift                                (modifié)
ios/.../PoteAgendaTests/KeychainServiceTests.swift             (nouveau)
ios/.../PoteAgendaTests/SupabaseServiceErrorMappingTests.swift (nouveau)
ios/.../PoteAgenda.xcodeproj/project.pbxproj                   (modifié, enregistre les 2 fichiers de test ci-dessus)
```
