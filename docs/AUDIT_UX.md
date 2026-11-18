# Audit UX de Rempart

Périmètre : code lu sur la branche `feature/audit-ux` (base `dev` @ f5083bb). Écrans : `OnboardingView`, `ContentView` (Sidebar, Dashboard, Journal), `UnlockView`, `AppsView`, `SitesView`, `CircleView`, `Components`, `Blob`, `AppBlocker` (overlay), `StayAlive`, `ApprovalService`, `Resources/block.html`.

## 0. Résumé et hypothèses

1. Rempart est une app macOS (SwiftUI) de discipline personnelle : blocage d'apps et de sites, retrait impossible sans déblocage approuvé par un proche via Messages.
2. Utilisateur principal : un étudiant en design qui veut se protéger de lui-même ; utilisateurs secondaires : d'autres personnes en autocontrôle, et surtout le **proche**, qui n'installe rien.
3. Problème central : maintenir un engagement pris à froid face à l'impulsion du moment, sans que la friction devienne de la frustration (donc de l'abandon ou du contournement).
4. Le point le plus fragile n'est pas le blocage, c'est la **chaîne de confiance technique** (daemon, 4 permissions macOS, lecture de `chat.db`) : si elle casse en silence, la promesse tombe.
5. Le point le plus délicat socialement est le **message au proche** : c'est lui qui porte le poids de la décision.

Hypothèses : usage solo sur un seul Mac ; le proche répond depuis son téléphone ; le proche connaît l'utilisateur personnellement ; pas de notion d'« urgence » modélisée aujourd'hui ; les durées de déblocage vont de 15 min à minuit. Aucune question bloquante.

---

## A. Diagnostic

| # | Constat | Pourquoi c'est un problème | Impact |
|---|---------|---------------------------|--------|
| 1 | **Promesse incohérente** : l'onboarding (`OnboardingView`, étape 0) dit « en écrivant une vraie raison », alors que seul le déblocage par un proche existe (`UnlockView.SelfUnlock.enabled = false`). `block.html` et l'overlay d'app disent aussi « explique-la ». | Heuristique 2 de Nielsen (correspondance système / monde réel) : on promet un mécanisme qui n'existe plus. Premier contact = attente fausse. | Élevé |
| 2 | **Le proche n'est configuré qu'après l'onboarding, et rien ne force à l'avoir.** Sans proche, aucun déblocage n'est possible, et les permissions Messages ne sont demandées nulle part dans l'onboarding. | Peak-end rule et loi de Hick : la première demande de déblocage échouera au pire moment (envie pressante), avec une erreur technique. | Élevé |
| 3 | **Santé du système peu lisible** : un seul bandeau « protection permanente » sur le dashboard ; l'état des permissions (Messages, disque, navigateurs) n'est visible que dans `CircleView` en texte long. Pas d'état « tout est OK ». | Heuristique 1 (visibilité de l'état du système). Une protection qui échoue en silence est pire qu'une absence de protection (fausse sécurité). | Élevé |
| 4 | **Message au proche trop centré sur le demandeur** : pas d'explication de ce qu'est Rempart, pas de « tu peux dire NON », pas de durée de validité. Pas de relance si le proche ne répond pas. | Charge émotionnelle : le proche craint d'être intrusif ou de décevoir. Sans « NON » légitimé, il dit OUI par politesse et le dispositif perd son sens. | Élevé |
| 5 | **Aucune voie pour une vraie urgence** ou un proche injoignable (ex. site de l'université bloqué la veille d'un examen). La seule issue est de contourner l'app (Force Quit, désinstallation du daemon). | Mauvaise friction : un blocage sans issue légitime pousse à l'abandon complet (« reactance » en psychologie). Respect de l'autonomie (théorie de l'autodétermination) compromis. | Élevé |
| 6 | **Retour d'information pauvre pendant l'attente** : « En attente… » en orange, bouton « Vérifier » manuel, pas d'heure d'envoi, pas de signal d'expiration, pas d'alerte si `chat.db` est illisible (le texte d'erreur n'apparaît qu'au clic). | Heuristique 1 et 9 (aide à la récupération d'erreur). L'utilisateur ne sait pas si le blocage vient du proche ou de la technique. | Moyen |
| 7 | **Ton parfois culpabilisant ou ambigu** : « Es-tu sûr ? », « En as-tu vraiment besoin ? », blob « angry » sur l'overlay et le dashboard (« Blocages aujourd'hui »), « Rien à signaler » pour le journal. | Un ton accusateur déclenche honte puis évitement. Le brief demande bienveillant et ferme. | Moyen |
| 8 | **Accessibilité partielle** : blob animé sans respect de « Réduire les animations », chips sélectionnées uniquement par la couleur et l'icône sans trait VoiceOver, graphique 7 jours sans équivalent textuel, polices en tailles fixes (`.system(size:)`), pas de raccourcis clavier pour les onglets, `block.html` animé sans `prefers-reduced-motion`. | WCAG 1.4.1 (couleur seule), 2.3.3 (animation), 4.1.2 (nom / rôle / valeur) ; HIG macOS (raccourcis ⌘1..6, VoiceOver). | Moyen |

---

## B. Recommandations priorisées

Triées du plus rentable au moins rentable (impact / effort).

| # | Recommandation | Problème | Effort | Impact | Priorité |
|---|----------------|----------|--------|--------|----------|
| 1 | Aligner tous les textes sur le mécanisme réel (proche, pas « raison écrite ») : onboarding, overlay, `block.html`, aide « Verrouillé » | 1 | S | 5 | Maintenant |
| 2 | Réécrire le message envoyé au proche (contexte, NON légitime, durée, OUI15 expliqué) | 4 | S | 5 | Maintenant |
| 3 | Onboarding : étape « Ton proche » (ajout + message test + permission Messages) avant la fin | 2, 3 | M | 5 | Maintenant |
| 4 | Carte « Santé du système » sur le dashboard (daemon, Messages, lecture des réponses, navigateurs) avec états OK / à corriger et un bouton d'action par ligne | 3, 6 | M | 5 | Maintenant |
| 5 | Voie « Urgence » : demander à un proche en mode « urgent » (message marqué), sinon délai d'attente long auto-appliqué à un seul élément (à valider, voir C.5) | 5 | M | 4 | Ensuite |
| 6 | Suivi d'une demande : heure d'envoi, « sans réponse depuis X min », bouton « Relancer », expiration visible | 4, 6 | M | 4 | Ensuite |
| 7 | Accessibilité : réduction des animations, traits VoiceOver, résumé textuel du graphique, raccourcis ⌘1..6 | 8 | S | 3 | Maintenant |
| 8 | Ton bienveillant et ferme : retirer les formulations accusatrices, ajouter un message de félicitation quand un blocage a tenu | 7 | S | 3 | Maintenant |
| 9 | Plusieurs proches : option « Demander à plusieurs, le premier OUI gagne » | 4, 5 | M | 3 | Plus tard |
| 10 | Rappel d'engagement à froid : écran « Pourquoi je bloque ça » écrit à l'onboarding, relu dans la demande | 7 | M | 3 | Plus tard |
| 11 | Désinstallation guidée (commande + explication) dans l'app | cas limites | M | 2 | Plus tard |
| 12 | Respect de Dynamic Type : passer des tailles fixes à des styles relatifs | 8 | L | 2 | Plus tard |

---

## C. Détail des 5 meilleures recommandations

### C.1 Aligner la promesse sur le mécanisme réel

**Comportement** : partout où l'app parle de « raison écrite » ou d'« expliquer », on parle d'un **proche qui décide**. L'utilisateur sait d'avance qu'il ne se débloque pas seul.

**Microcopy** (fr-CA) :
- Onboarding, étape 0 : « Rempart bloque tes apps et sites distrayants. Pour en débloquer un, tu demandes à un proche : il reçoit un message et répond OUI ou NON. »
- Overlay app : titre « *Apple TV* est bloqué » ; texte « Tu l'as bloqué pour une bonne raison. Si c'est vraiment important, demande à un proche. »
- `block.html` : « *youtube.com* est bloqué. Tu as choisi de le bloquer. Si c'est important, ouvre Rempart et demande à un proche. »
- Aide « Verrouillé » : « Pour le retirer, demande d'abord un déblocage à un proche. »

**États** : sans objet (texte). **Implémentation** : `OnboardingView.swift`, `AppBlocker.swift` (`BlockOverlayView`), `Resources/block.html`, `Components.swift` (`RuleAction.help`). Fait dans ce lot.

### C.2 Le message au proche

**Comportement** : le proche comprend en 5 secondes qui demande, quoi, combien de temps, pourquoi, et qu'un NON est une réponse normale.

**Proposition** :

```
Salut ! Justin utilise Rempart pour limiter son temps d'écran.
Il demande à débloquer YouTube pendant 1 h.

« Je regarde un film ce soir »

Réponds :
  OUI    -> accepté (1 h)
  OUI15  -> accepté pour 15 min seulement
  NON    -> refusé

Dire NON, c'est l'aider : il t'a choisi pour ça. Sans réponse de ta part, rien n'est débloqué.
```

**Variantes** : durée ≤ 15 min → « Réponds OUI ou NON. » (déjà présent).
**États** : envoi réussi (bannière), échec (voir C.4), pas de réponse (voir C.5 / reco 6).
**Implémentation** : `ApprovalService.sendRequest` (chaîne `body`) et `sendTest`. Fait dans ce lot.

### C.3 Onboarding avec étape « Ton proche »

**Wireframe (étape 4 sur 5)** :

```
+--------------------------------------------------+
| (blob happy)                                     |
| Qui peut t'aider à tenir bon ?                   |
| Cette personne recevra tes demandes de déblocage |
| dans Messages. Elle répond OUI ou NON.           |
|                                                  |
| [ Prénom      ] [ Numéro ou courriel iMessage ]  |
|                          [ Envoyer un message test ] |
|                                                  |
| (i) Tu peux passer cette étape, mais sans proche |
|     tu ne pourras rien débloquer.                |
|                                                  |
| Retour                              [ Continuer ]|
+--------------------------------------------------+
```

**États** : vide (champs vides, « Continuer » actif mais avec avertissement), erreur (« Impossible d'envoyer. Autorise Rempart à contrôler Messages dans Réglages > Confidentialité > Automatisation. » + bouton d'ouverture), chargement (« Envoi… »), succès (coche + « Message envoyé à Camille »).
**Implémentation** : ajouter un `case` dans `OnboardingView` (tableau des titres et blobs passé à 5 entrées), réutiliser `store.addContact` et `ApprovalService.sendTest`. Effort M. **Non fait dans ce lot** (hors quick wins) ; le texte de l'étape actuelle est déjà clarifié.

### C.4 Carte « Santé du système »

**Wireframe (dashboard, sous le bandeau)** :

```
+--------------------------------------------------+
| Tout est en ordre                       [ v ]    |
|  ✓ Protection permanente installée               |
|  ✓ Messages autorisé (envoi)                     |
|  ! Lecture des réponses désactivée  [ Corriger ] |
|  ✓ Navigateurs autorisés                         |
+--------------------------------------------------+
```

**Microcopy** : « Rempart ne peut pas lire les réponses de ton proche. Autorise l'accès complet au disque, puis relance l'app. » Pas de jargon : on dit « lire tes messages pour trouver OUI ou NON » plutôt que « chat.db ».
**États** : chargement (« Vérification… »), tout OK (carte repliée, une ligne), problème (carte ouverte, orange), erreur inconnue (« Diagnostic impossible. Réessaie. »).
**Implémentation** : nouvelle `HealthCard` dans `ContentView.swift` ; exposer `ApprovalService.canReadMessages()` (actuellement `private`), `HostsHelperInstaller.isInstalled`, un test AppleScript léger pour l'automatisation. Rafraîchir à l'apparition de la fenêtre (`NSApplication.didBecomeActiveNotification`).

### C.5 Voie « Urgence » sans casser la règle

Deux options :

- **Option A (recommandée)** : dans `UnlockView`, case « C'est urgent » qui préfixe le message au proche (« URGENT ») et envoie une relance après 5 min sans réponse. Ne change aucune règle de sécurité.
- **Option B** : déblocage solo différé (réactivation de `SelfUnlock`) avec attente longue (ex. 15 min) et limité à un élément, à une fréquence par jour. Plus d'autonomie, mais réintroduit un chemin que l'utilisateur peut spammer.

Compromis : A respecte l'engagement mais dépend de la disponibilité du proche ; B règle l'urgence réelle mais érode la règle. Recommandé : A d'abord ; si le proche est injoignable trop souvent dans les logs de validation, tester B avec plafond (1 par jour).
**États** : en attente (« Camille n'a pas répondu depuis 5 min »), relance envoyée, expirée (« Sans réponse. Rien n'a été débloqué. »).
**Implémentation** : champ `urgent` dans `ApprovalRequest` (`Models.swift`, Codable avec valeur par défaut pour l'ancien `state.json`), relance dans `ApprovalService.poll()`.

---

## D. Parcours redessinés

### D.1 Demander un déblocage à un proche

**Avant**
1. Clic sur « Verrouillé » (ou overlay) puis onglet Débloquer.
2. Choisir les éléments, la durée, le proche.
3. Écrire un message d'au moins 15 caractères.
4. Envoyer ; bannière « Message envoyé ».
5. Demande « En attente… » ; cliquer « Vérifier » à la main.
6. Pause active sur le dashboard, ou « Refusé » avec notification.

**Après**
1. Même point d'entrée, avec l'élément déjà préselectionné et le proche par défaut si un seul.
2. Durée proposée par défaut selon l'usage (ex. 1 h) et rappel « Dernier déblocage il y a X ».
3. Message court avec suggestions cliquables (« Pour un devoir », « Pour me détendre », « Urgent »).
4. Aperçu du message tel que le proche le recevra (avec OUI / OUI15 / NON).
5. Envoi : carte d'état « Envoyé à 14 h 02 · en attente » avec relance et annulation.
6. Réponse : notification claire, pause visible, et fin de pause annoncée 1 min avant.

### D.2 Onboarding

**Avant** : 1) bienvenue, 2) apps, 3) sites, 4) autorisations (démarrage, daemon, rappel navigateur). Le proche et Messages arrivent plus tard.

**Après** : 1) bienvenue + règle du jeu en une phrase, 2) apps, 3) sites, 4) **proche** (ajout + message test), 5) autorisations avec pourquoi / quand pour chacune et un état clair (accordé / à faire), 6) résumé « Voici ce qui est protégé » avec la carte de santé.

---

## E. Quick wins (moins d'une heure chacun)

Implémentés sur cette branche (voir historique git) :

1. **Onboarding** : phrase d'accueil alignée sur le déblocage par un proche (`OnboardingView`).
2. **Message au proche** : contexte, NON légitimé, durée et OUI15 clairs (`ApprovalService`).
3. **Overlay d'app** : ton bienveillant, bouton « Demander à un proche » (`AppBlocker`).
4. **`block.html`** : texte bienveillant, `prefers-reduced-motion`, bouton de repli clair.
5. **Aide « Verrouillé »** : mentionne le proche (`Components.RuleAction`).
6. **Blob** : respecte « Réduire les animations » et est caché de VoiceOver (`Blob.swift`).
7. **Chips Débloquer** : trait `isSelected` pour VoiceOver (`UnlockView`).
8. **Graphique 7 jours** : étiquette VoiceOver textuelle par jour (`WeekChart`).
9. **Raccourcis ⌘1 à ⌘6** pour changer d'onglet (`RempartApp`) et libellé VoiceOver de l'état « Protégé / Débloqué » (`Sidebar`).
10. **Microcopy** : états vides, erreurs d'envoi, journal, et contraste du texte secondaire relevé (`Theme.muted`).

---

## F. Plan de validation

**Participants** : 5 personnes (2 étudiants en design, 2 non-techniques, 1 proche potentiel qui ne connaît pas l'app).

**Tâches**
1. Installer et configurer Rempart jusqu'au premier blocage (observer l'abandon et les hésitations aux permissions).
2. Bloquer YouTube, puis tenter de le retirer (compréhension de « Verrouillé »).
3. Demander un déblocage de 30 min à un proche.
4. (Côté proche) Lire le message reçu et répondre sans aide.
5. Simuler un proche qui ne répond pas pendant 10 min ; observer la réaction.
6. Rouvrir l'app après la fin de la pause ; décrire l'état de l'app.

**Métriques**
- Onboarding : taux d'abandon par étape, temps total, nombre de permissions accordées.
- Usage : demandes de déblocage par semaine, taux d'approbation (un taux proche de 100 % signale un proche trop complaisant), durée moyenne accordée, part de OUI15.
- Fiabilité : délai médian entre réponse du proche et déblocage appliqué, nombre de demandes jamais résolues.
- Contournement : nombre de retraits de blocage, fréquence de Force Quit ou de désinstallation du daemon.
- Rétention : utilisateurs actifs à J7 et J30.

**Questions qualitatives**
- Utilisateur : « À quel moment t'es-tu senti·e bloqué·e injustement ? » « Qu'as-tu compris de ce que Rempart peut faire sans ton accord ? »
- Proche : « Qu'as-tu ressenti en recevant le message ? » « Te sentirais-tu à l'aise de répondre NON ? »

**Critère de succès** : ≥ 4 participants sur 5 réussissent les tâches 1 à 4 sans aide ; le proche répond correctement sans explication ; zéro demande bloquée par une erreur technique non comprise.
