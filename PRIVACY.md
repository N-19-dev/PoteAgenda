# Politique de confidentialité — PoteAgenda

_Dernière mise à jour : 21 août 2026_

## Ce que PoteAgenda fait

PoteAgenda aide un groupe d'amis à trouver un créneau commun sans révéler le
contenu de l'agenda de chacun. Les autres membres ne voient jamais le titre,
la couleur ou les détails d'un événement — seulement "Occupé" / "Libre" et
les intervalles horaires correspondants, sauf si tu actives explicitement le
partage du titre pour un ami précis.

## Données collectées

- **Compte** : adresse email, pseudo, mot de passe (géré par Supabase Auth,
  jamais stocké en clair par nous).
- **Agenda** : les créneaux que tu ajoutes manuellement ou importes (calendrier
  iOS via EventKit, ou fichier/URL .ics) — titre, horaires, couleur.
- **Relations** : tes demandes d'ami, groupes, et les sorties auxquelles tu
  participes ou que tu organises (y compris les messages du fil de
  discussion d'une sortie).
- **Préférences de partage** : les amis à qui tu as choisi de montrer le
  titre réel de tes événements.

## Ce qui est partagé, et avec qui

- Les membres d'un groupe commun ou tes amis (amitié acceptée) voient
  uniquement tes plages "Occupé" (heures de début/fin), jamais le titre, la
  couleur ni le lieu d'un événement — sauf si tu as explicitement activé le
  partage du titre pour cette personne.
- Ces données transitent exclusivement par des fonctions serveur dédiées
  (`get_group_busy_events`, `get_friends_busy_events`) qui n'exposent que
  ces informations minimales, jamais un accès direct à ton agenda brut.
- Nous ne partageons aucune donnée avec des tiers, ne faisons pas de
  publicité et n'utilisons aucun outil de tracking.

## Stockage et sécurité

- Les données sont hébergées chez Supabase (PostgreSQL) avec des règles de
  sécurité au niveau des lignes (Row Level Security) qui limitent l'accès
  aux données brutes à leur propriétaire uniquement.
- Le jeton de session est stocké dans le Trousseau (Keychain) de ton
  appareil, pas dans un stockage non chiffré.
- L'accès à tes calendriers iOS (EventKit) reste local à l'appareil : seuls
  les créneaux que tu choisis de connecter sont envoyés à nos serveurs.

## Tes droits

- Tu peux supprimer une indisponibilité, un calendrier connecté, ou
  quitter un groupe/une amitié à tout moment depuis l'app.
- Tu peux supprimer définitivement ton compte et toutes les données
  associées depuis Réglages > Compte > "Supprimer mon compte". Cette action
  est irréversible.
- Pour toute question, contacte-nous à [adresse email à renseigner].

## Contact

[adresse email ou lien de contact à renseigner avant publication]
