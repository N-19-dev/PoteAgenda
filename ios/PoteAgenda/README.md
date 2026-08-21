# PoteAgenda iOS

Application iOS SwiftUI native pour PoteAgenda. Elle utilise le backend
Supabase du projet (schema, RLS et RPC dans `supabase/migrations/`).

## Configuration

1. Duplique `PoteAgenda/Resources/Supabase.example.plist` en
   `PoteAgenda/Resources/Supabase.plist`.
2. Renseigne :
   - `SUPABASE_URL`
   - `SUPABASE_PUBLISHABLE_KEY`
3. Ouvre `PoteAgenda.xcodeproj` dans Xcode.
4. Dans la target `PoteAgenda`, verifie ton `Team` Apple et lance sur iPhone ou
   simulateur.

## Lancer les tests

Dans Xcode : `Cmd+U` (ou Product → Test), avec la target `PoteAgendaTests`
sélectionnée. Contient notamment :

- `DateHelpersTests`, `AgendaModelsTests`, `InvitationLogicTests` — logique
  métier.
- `KeychainServiceTests` — vérifie que la session est stockée avec
  l'accessibilité Keychain attendue (`AfterFirstUnlockThisDeviceOnly`).
- `SupabaseServiceErrorMappingTests` — vérifie qu'aucune erreur backend
  brute (SQL, RLS) ne fuit dans les messages affichés à l'utilisateur.

## Etat du portage

Ce socle couvre deja :

- connexion et inscription email/mot de passe ;
- session persistante ;
- agenda personnel en vue jour ;
- ajout et suppression d'indisponibilites manuelles ;
- recherche de profils, demande d'ami et reponse aux demandes ;
- liste et creation de groupes ;
- vue matcher via la RPC `get_group_busy_events` ;
- invitations/sorties avec acceptation ou refus.

Restera a durcir avant publication App Store :

- import/resync ICS natif ou via Edge Function ;
- notifications push ;
- tests UI et verification sur appareils reels ;
- generation d'icones App Store ;
- heberger `PRIVACY.md` (URL) et l'ajouter a la fiche App Store Connect + un
  lien depuis l'app (AuthView/SettingsView) ;
- compte developpeur Apple + creation de la fiche App Store Connect.
