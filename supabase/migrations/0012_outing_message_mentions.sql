-- Permet de taguer certains participants d'une sortie dans un message
-- (ex. "@Julie peux-tu confirmer ?"). Les ids tagués sont stockés
-- explicitement (plutôt que re-parsés depuis le texte à chaque lecture) afin
-- de fiabiliser la notification "tu as été mentionné·e" (cf. app iOS), sans
-- dépendre du texte libre du message.
--
-- Le client (web/iOS) restreint la sélection aux participants de la sortie,
-- mais aucune contrainte serveur ne le garantit : ce n'est pas une frontière
-- de sécurité, seulement un confort d'UI, donc pas de trigger de validation.

alter table public.outing_messages
  add column mentioned_user_ids uuid[] not null default '{}';
