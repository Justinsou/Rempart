# Rempart — guide pour une IA / développeur

Document de contexte pour comprendre **ce qu’est Rempart**, **comment ça marche**, et **où toucher le code** sans tout relire.

## En une phrase

Rempart est une **app macOS native (SwiftUI)** qui bloque des **apps** et des **sites web** pour réduire le temps d’écran. C’est une alternative personnelle à Opal. Le déblocage temporaire se fait surtout via **l’approbation d’un proche par Messages** (réponses `OUI` / `OUI15` / `NON`).

## Objectifs produit

- Empêcher l’ouverture d’apps choisies (ex. Apple TV).
- Empêcher l’accès à des sites choisis (ex. youtube.com), dans les navigateurs et au niveau système.
- Rendre le retrait d’un blocage difficile : on peut **ajouter** librement, mais **retirer** seulement pendant un déblocage actif (ou pendant l’onboarding).
- Rendre la sortie de l’app difficile (le X cache la fenêtre ; quitter demande confirmation + délai).
- Rester utilisable **sans compte Apple Developer payant** ni API Screen Time (pas d’entitlement Family Controls).

## Stack & build

| Élément | Détail |
|--------|--------|
| Langage | Swift 6 / SwiftUI |
| Projet | Swift Package Manager — [`Package.swift`](../Package.swift) |
| Cible | macOS 14+, Apple Silicon |
| Bundle ID | `com.rempart.app` |
| Build / install | `scripts/build-app.sh` → compile release, crée `build/Rempart.app`, signe, copie dans `/Applications` |
| Signature | Identité locale « Rempart Local Signing » si présente (garde TCC entre builds), sinon ad hoc |
| Entitlements | [`scripts/Rempart.entitlements`](../scripts/Rempart.entitlements) (Apple Events) |
| Données user | `~/Library/Application Support/Rempart/state.json` |
| Règles partagées | `/Users/Shared/Rempart/hosts-rules.txt` et `apps-rules.txt` |

Commande typique :

```bash
scripts/build-app.sh          # build + install /Applications
scripts/build-app.sh --no-install
```

## Architecture (vue d’ensemble)

```
UI (SwiftUI)  →  RulesStore (JSON)  →  AppBlocker / WebBlocker
                                  →  hosts-rules.txt + apps-rules.txt
                                  →  LaunchDaemon root (ferme apps + réécrit /etc/hosts)
Déblocage proche → Messages (envoi) + lecture réponses (chat.db / AppleScript)
```

### Fichiers importants

| Chemin | Rôle |
|--------|------|
| `Sources/Rempart/RempartApp.swift` | Entrée app, thème, fenêtres, MenuBarExtra, login item |
| `Sources/Rempart/Models/Models.swift` | `BlockedApp`, `BlockedSite`, `UnlockSession`, `TrustedContact`, `ApprovalRequest`, `AppState` |
| `Sources/Rempart/Services/RulesStore.swift` | Source de vérité, persistance, calcul bloqué/débloqué, sync fichiers règles |
| `Sources/Rempart/Services/AppBlocker.swift` | Détecte apps lancées / au premier plan, terminate, overlay |
| `Sources/Rempart/Services/WebBlocker.swift` | AppleScript : lit URL onglets Safari/Chrome/Brave/Edge/Arc, redirige vers `block.html` |
| `Sources/Rempart/Services/HostsHelperInstaller.swift` | Installe/désinstalle le LaunchDaemon (mot de passe admin) |
| `Sources/Rempart/Services/ApprovalService.swift` | Envoi Messages + poll réponses OUI/NON |
| `Sources/Rempart/Services/StayAlive.swift` | X = masquer fenêtre ; quit avec délai 30 s |
| `Sources/Rempart/Views/*` | UI : dashboard, apps, sites, débloquer, proches, journal, onboarding |
| `scripts/rempart-hosts-daemon.sh` | Daemon root : `/etc/hosts` + kill apps bloquées |
| `scripts/install-daemon.sh` | Install / uninstall daemon |
| `Resources/block.html` | Page « Site bloqué » |

## Comment marche le blocage

### Apps

1. L’utilisateur marque une app (bundle ID + chemin).
2. **Tant que Rempart tourne** : `AppBlocker` ferme l’app si elle est bloquée et pas dans une `UnlockSession` active.
3. **Même si Rempart est quitté** : le LaunchDaemon lit `apps-rules.txt` (`until|path`) et `kill -9` les process dont le chemin match (whitelist de dossiers : `/Applications`, `/System/Applications`, `~/Applications`).
4. Une ligne `until` dans le futur = débloqué jusqu’à ce timestamp ; `0` = toujours bloqué.

### Sites

Deux couches :

1. **WebBlocker** (toutes ~1,5 s) : AppleScript sur l’onglet actif ; si le host matche un domaine bloqué (y compris sous-domaines), redirection vers `Resources/block.html#domaine`.
2. **Daemon + `/etc/hosts`** : écrit `0.0.0.0` / `::` pour le domaine et variantes `www.`, `m.`, `mobile.`. Compense Firefox et le cas où Rempart est fermé.

`RulesStore.syncHosts()` régénère les fichiers lus par le daemon.

### Retrait vs ajout

- **Ajouter** une app/site : toujours possible (avec popup de confirmation UI).
- **Retirer** : seulement si `canRemove*` (pas encore onboardé **ou** élément actuellement débloqué via session). Sinon bouton « Verrouillé » → ouvre l’onglet Débloquer avec préselection.

## Déblocage / « pause »

### Mode actuel (UI)

Seul le mode **« Demander à un proche »** est exposé dans l’UI.

Flag dans `UnlockView` :

```swift
private enum SelfUnlock {
    static let enabled = false  // mettre true pour réafficher « Par moi-même »
}
```

Le code du mode solo (justification ≥ 50 caractères + attente 60 s + `addUnlock`) est **conservé** mais inaccessible via l’UI tant que `enabled == false`.

### Flux proche (actif)

1. Onglet **Proches** : ajouter prénom + numéro ou e-mail iMessage.
2. Onglet **Débloquer** : choisir items, durée, proche, message (≥ 15 caractères).
3. `ApprovalService.sendRequest` envoie un iMessage via AppleScript (repli : ouvre `sms:`).
4. Le proche répond **`OUI`**, **`OUI15`** (15 min) ou **`NON`**.
5. Rempart poll (~5 s) : AppleScript et/ou `~/Library/Messages/chat.db` (nécessite **Accès complet au disque** + Automatisation Messages).
6. Si approuvé → `RulesStore.addUnlock` + entrée journal.

Demandes : annuler (pending → cancelled), supprimer (terminées), « Tout supprimer ».

### Sessions

`UnlockSession` : liste de clés `app:<bundleID>` / `site:<domain>`, `start`/`end`, `reason`.  
Tant que `now < end`, l’élément n’est plus « bloqué ». À la fin, reblocage automatique (daemon + app).

## Persistence & onboarding

- `AppState` JSON dans Application Support.
- Premier lancement : sheet onboarding (apps, sites, login item, install daemon).
- Menu bar : blob bleu (ou compte à rebours si pause active).
- Quit : `QuitGuard` (30 s) ; fermer la fenêtre ne quitte pas.

## Permissions macOS à connaître

| Permission | Pourquoi |
|------------|----------|
| Automatisation → Navigateurs | WebBlocker |
| Automatisation → Messages | Envoi / lecture réponses |
| Accès complet au disque | Lire `chat.db` pour OUI/NON |
| Mot de passe admin | Installer LaunchDaemon + écrire `/etc/hosts` |

Sans le daemon à jour, les apps peuvent se rouvrir si Rempart est quitté. Le dashboard affiche un bandeau si install/update nécessaire.

## Design UI

- Thème sombre forcé, accent bleu, mascottes « blob » (`Blob.swift`, moods calm/happy/angry/sleepy/sad).
- Style inspiré Muse / Grok / COROS (cartes, gros chiffres, graphique 7 jours).
- Boutons primaires : texte **blanc** sur bleu (`PillButton`, `PrimaryCTA`).
- Confirmation avant blocage : `BlockConfirm` + sheet.

## Branches Git (habitude du repo)

- `main` — stable mergée
- `dev` — intégration
- Features : `feature/...` (ex. `feature/ui-contraste-popup-icone`)

Repo : https://github.com/Justinsou/Rempart

## Limites assumées

- Outil de **discipline**, pas un contrôle parental inviolable (Force Quit, retrait daemon avec admin, etc.).
- Redirection d’onglets limitée aux navigateurs AppleScript ; hosts couvre le reste.
- Lecture Messages dépend des permissions TCC ; signature stable recommandée pour ne pas les perdre à chaque build.
- Pas d’API Screen Time.

## Comment réactiver la pause solo

1. Dans `Sources/Rempart/Views/UnlockView.swift`, mettre `SelfUnlock.enabled = true`.
2. Rebuild : `scripts/build-app.sh`.

## Checklist debug rapide

1. App bloquée s’ouvre encore → daemon installé/à jour ? `apps-rules.txt` contient le bon chemin ?
2. Site accessible → domaine dans `hosts-rules.txt` ? section Rempart dans `/etc/hosts` ? cache DNS ?
3. OUI reçu mais pas débloqué → Accès complet au disque + diagnostic « Vérifier » / « Vérifier la lecture des réponses » dans Proches.
4. Autorisations perdues après rebuild → signer avec « Rempart Local Signing ».
