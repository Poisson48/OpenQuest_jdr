# Protocole de session — v2

> Étape 3 du [plan d'adaptation](rapport-letsrole/ADAPTATION.md).
> **Aucune ligne reprise** : les mécanismes (corrélation, ticket, rate-limit, erreurs
> typées, resynchronisation) ont été réimplémentés pour notre architecture —
> **P2P (hôte Godot autoritaire) + serveur de pooling**.

## Rôles

| Composant | Rôle | Autorité |
|---|---|---|
| `server/` (Node/TS) | annuaire des salons + signalisation WebRTC/ENet + tickets | limitée : matchmaking |
| Hôte Godot (`MultiplayerManager`) | état de partie, jets, cartes | **autoritaire** |
| Clients | affichage, actions soumises à l'hôte | aucune |

## Enveloppe

Tout message reste **plat** (`type`), et toute requête peut porter un `req_id` :

```json
{ "type": "join_room", "code": "1234", "req_id": "abcd1234-3" }
```

Le serveur renvoie **le même `req_id`** dans sa réponse ou dans l'erreur. Côté
Godot, `_send_request()` génère l'identifiant, `_pending_requests` garde une
échéance (`REQUEST_TIMEOUT = 8 s`) et `_expire_pending()` émet une erreur réseau
si le serveur ne répond pas. Côté serveur, `withReqId()`/`fail()` font l'écho.

## Codes d'erreur

`BAD_JSON`, `UNKNOWN_TYPE`, `INVALID_PAYLOAD`, `RATE_LIMITED`, `GM_ONLY`,
`JOIN_FAILED`, `ROOM_FULL`, `ROOM_NOT_FOUND`, `NOT_IN_ROOM`,
`TARGET_NOT_FOUND`, `TICKET_INVALID`, `TICKET_EXPIRED`, `ALREADY_IN_ROOM`,
`INTERNAL`.

Le client mappe chaque code vers un texte français (`POOLING_ERRORS`) puis émet
`p2p_error` — l'UI n'a plus à interpréter une chaîne serveur.

## Validation

`server/src/lobby/validate.ts` valide chaque message **avant** tout traitement
(zod, schémas par type, champs inconnus ignorés). Une requête invalide reçoit
`INVALID_PAYLOAD` avec le chemin du champ fautif, sans toucher à l'état du salon.

## Limitation de fréquence

`server/src/lobby/rate_limit.ts` : fenêtre glissante par clé `joueur:type`.
Au-delà du seuil → `RATE_LIMITED` (le socket reste ouvert) ; au-delà du **double**
→ même réponse puis fermeture de la socket. Seuils par défaut : `signal`
240/s, `ping` 4/s, `join_room` 6/5 s, `create_room` 3/5 s, etc.

## Ticket de session (reprise après coupure)

1. À l'entrée dans un salon (`create_room`, `join_room`), le serveur émet
   `session_ticket` : `{ ticket, expiresAt, roomCode }` (TTL 2 min, **usage unique**).
2. Le client le conserve (`session_ticket`, `session_ticket_expires_at`, persisté
   dans `user://multiplayer_settings.cfg`) et, à la prochaine connexion pooling,
   envoie `resume_session` dès le `welcome`.
3. Le serveur consomme le ticket, **reprend la même identité** (même `playerId`,
   même nom, même personnage enregistré), réintègre le salon s'il existe encore
   et émet `resumed` + un **nouveau** ticket.
4. Si le salon n'existe plus (MJ parti), `resumed` porte `room: null` : l'identité
   est restaurée, le joueur peut rejoindre une autre partie.

Limites assumées : la reprise ne ressuscite pas un salon dissous (le départ du MJ
dissout la partie) ; en P2P la reconnexion à l'hôte redemande un **état complet**
(voir ci-dessous).

## Resynchronisation d'état (hôte → joueur)

Le pooling ne transporte pas l'état de jeu (P2P). Après (re)connexion P2P, le
joueur appelle `request_state_resync.rpc_id(1, player_id)` ; l'hôte
(`request_state_resync`, RPC) rediffuse l'état complet via `broadcast_state()`
(`sync_game_state`). Cela couvre : reconnexion ENet, reprise WebRTC, joueur qui
arrive en cours de partie.

## Fichiers

| Côté | Fichier |
|---|---|
| serveur | `src/lobby/protocol.ts`, `src/lobby/validate.ts`, `src/lobby/rate_limit.ts`, `src/lobby/tickets.ts`, `src/pooling/server.ts`, `src/lobby/types.ts` |
| client | `game/scripts/multiplayer/multiplayer_manager.gd` |
| tests | `server/scripts/test_lobby.ts` (unités, 81 vérif.), `server/scripts/test_lobby_protocol.ts` (**contrat de protocole v2**, 302 vérif. au 2026-11-17, pur, sans port), `server/scripts/test_lobby_integration.ts` (bout en bout, 18 vérif.), `game/scripts/tests/session_protocol_test.gd` — les comptes évoluent avec les tests |

Le contrat v2 (13 types client→serveur, 12 types serveur→client, codes d'erreur,
tickets, rate-limit) est **gelé** par `test_lobby_protocol.ts` et décrit dans
[MULTIPLAYER.md §3.3](MULTIPLAYER.md#33-contrat-de-protocole-v2-référence).

```powershell
cd server; npm test          # lobby (unités) + contrat de protocole + lobby (bout en bout)
./scripts/run_tests.ps1 -Filter 'session_protocol_test'
```

Les **dés ne sont plus testés côté serveur** : `npm test` ne couvre que le pooling
(lobby + protocole + intégration). L'unique implémentation exécutable est le
moteur GDScript `game/scripts/core/rules/dice_engine.gd`, testé par
`dice_engine_test.gd` sur la spec `game/data/tests/dice_cases.json` (la chaîne
TypeScript est archivée dans `server/legacy/`, ADR-005 — voir [MOTEUR_DES.md](MOTEUR_DES.md)).

## Hors périmètre v2

- migration d'hôte (le MJ quitte → partie dissoute, comme avant) ;
- chiffrement applicatif (le transport reste ws:// en LAN) ;
- persistance des salons au redémarrage du serveur.
