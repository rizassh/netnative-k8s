# PROGRESS — journal de bord

Une entrée par session. Format : ce qui est fait / ce qui bloque / prochaine étape.
Ce fichier est la **source de vérité du suivi** : c'est ce que je colle en début de
session (ici ou à Claude Code) pour reprendre le fil.

---

## 2026-07-08 — Socle
- **Fait** : VM Debian 13 (QEMU/KVM) créée, accès SSH depuis le Mac. Docker Engine
  (dépôt officiel) + containerlab installés. `hello-world` et `clab version` OK.
- **Bloqué** : rien.
- **Prochaine étape** : phase 1 — déployer la fabric leaf-spine et valider l'underlay eBGP.

## 2026-07-08 — Phase 1 (démarrage)
- **Fait** : repo initialisé (README, PROGRESS, CLAUDE, .gitignore). Topologie
  containerlab + configs FRR posées dans `clab/`.
- **Bloqué** : —
- **Prochaine étape** : `clab deploy`, vérifier les sessions eBGP (`show bgp summary`),
  valider la joignabilité host1 ↔ host2 à travers la fabric + l'ECMP côté leaves.

## 2026-07-08 — Phase 1 (fabric déployée)
- **Fait** : `clab deploy` OK, 6 nœuds `up` (2 spines, 2 leaves, 2 hosts). Sessions
  eBGP underlay **Established** (ex. leaf1 AS65011 ↔ spine1 AS65001 / spine2 AS65002,
  loopbacks échangés). Hygiène repo : `.gitignore` corrigé — le motif `clab-*/`
  était neutralisé par un commentaire *inline* (non supporté par git), donc le dossier
  runtime `clab-leaf-spine/` généré par containerlab s'était retrouvé stagé ; désindexé
  via `git rm --cached` et désormais bien ignoré.
- **Validé** : joignabilité host1 ↔ host2 de bout en bout à travers la fabric
  (ping 0% loss). **ECMP** confirmé côté leaf : loopback distant `10.255.0.12/32`
  installé avec double next-hop (`10.0.0.0`/spine1 + `10.0.0.4`/spine2, `weight 1`).
  → underlay eBGP RFC 7938 opérationnel et load-balancé. Phase 1 terminée.
- **Bloqué** : —
- **Prochaine étape** : Phase 2 — cluster **kind** + **Cilium**, faire peerer le
  control plane BGP de Cilium avec les leaves ; annoncer pod CIDR + pool LoadBalancer
  dans la fabric.

## 2026-07-11 — Phase 2 (démarrage : cluster kind + attache à la fabric)
- **Fait** :
  - Cluster **kind** `l3bgp-cluster` créé (`k8s/config.yaml`), **single-node pour
    l'instant** (`l3bgp-cluster-control-plane`, image `kindest/node:v1.35.0`, up) —
    un **2ème nœud** sera ajouté plus tard. Config avec `disableDefaultCNI: true` :
    on désactive le CNI par défaut de kind pour installer **Cilium** à la place
    (control plane BGP requis en phase 2).
  - Topologie clab retravaillée pour préparer l'attache du cluster à la fabric :
    `host1`/`host2` (netshoot) **commentés** (gardés comme référence), remplacés par
    un nœud `external-node1` de kind **`ext-container`** câblé sur `leaf1:eth3`.
    Objectif : rattacher un conteneur existant (le nœud kind) à la fabric plutôt
    qu'un host synthétique. **Design** : chaque nœud kind est rattaché à **un seul
    leaf** (pas de dual-homing par nœud) ; la redondance viendra du 2ème nœud sur
    l'autre leaf.
- **Bloqué / à finir** :
  - Fabric clab **pas redéployée** après la modif : le câblage `ext-container` est
    posé sur disque mais **ni déployé ni validé** (`clab inspect` = aucun lab actif).
  - `external-node1` (`ext-container`) **ne référence pas encore le conteneur cible**
    (nom du nœud kind à préciser) — à vérifier avant `clab deploy`.
  - Cilium **pas encore installé** ; peering BGP leaves ↔ Cilium **pas commencé**.
- **Prochaine étape** :
  1. Finaliser le nœud `ext-container` (pointer vers le conteneur kind) et redéployer
     la fabric ; vérifier le lien leaf1 ↔ nœud kind.
  2. Installer **Cilium** sur `l3bgp-cluster` (CNI + BGP control plane).
  3. Configurer le peering eBGP Cilium ↔ leaf1 (et leaf2 ?), annoncer le **pod CIDR**
     puis un **pool LoadBalancer** dans la fabric ; valider l'annonce côté leaves
     (`show bgp ipv4 unicast`).
- **Décisions actées** : 2ème nœud kind prévu plus tard ; **1 nœud = 1 leaf**
  (nœud suivant sur `leaf2`) ; anciens `host1`/`host2` conservés en commentaire.

## 2026-07-15 — Phase 2 (cluster 3 nœuds attaché à la fabric + Cilium installé)
- **Fait** :
  - **Cluster kind passé à 3 nœuds** (`k8s/config.yaml`) : 1 `control-plane` + 2 `worker`,
    image `kindest/node:v1.35.0`, tous `Ready`. `disableDefaultCNI: true` conservé.
    Le passage à 2 workers permet de valider un vrai **multi-nœud** (trafic pod↔pod
    inter-nœud, donc inter-leaf) plutôt qu'un cluster dégénéré à 1 nœud.
  - **Attache à la fabric concrétisée** (`clab/leaf-spine.clab.yml`) : les nœuds
    `ext-container` génériques sont remplacés par les **vrais conteneurs kind**,
    référencés par leur nom exact — `l3bgp-cluster-worker` et `l3bgp-cluster-worker2`.
    Câblage conforme au design **1 nœud = 1 leaf** :
    - `leaf1:eth3` ↔ `l3bgp-cluster-worker:eth1` → `10.1.1.10/24`, default via `10.1.1.1`
    - `leaf2:eth3` ↔ `l3bgp-cluster-worker2:eth1` → `10.1.2.10/24`, default via `10.1.2.1`
    Les blocs `host1`/`host2` commentés ont été supprimés (l'historique git les garde ;
    du code mort commenté n'apporte rien).
  - **Cilium installé** sur `l3bgp-cluster` via Helm : 3/3 pods `cilium` Running
    (un par nœud). Le cluster a donc un CNI fonctionnel.
- **Validé** :
  - Underlay eBGP toujours **Established** sur leaf1 (AS65011 ↔ spine1 AS65001 /
    spine2 AS65002) — la refonte du câblage n'a pas cassé la phase 1.
  - **Niveau 3 « nu » de bout en bout** : `leaf1 → 10.1.1.10` et `leaf2 → 10.1.2.10`
    en **0% loss**. Chaque nœud kind est joignable depuis son leaf via son lien `eth1`
    dédié → le plan de câblage physique/L3 est bon, la base est prête pour le BGP.
- **Pas encore fait** : aucun pod applicatif déployé sur les workers ; **BGP Cilium
  pas commencé** (pas de `CiliumBGPClusterConfig`, aucun peering leaf ↔ Cilium).
- **Bloqué / dette à traiter** :
  1. **L'install Cilium n'est pas dans le repo** — elle a été faite en Helm avec des
     valeurs passées en ligne de commande (`ipam.mode=kubernetes`, `image.pullPolicy`).
     Ça viole la convention « une seule source de vérité : ce repo » : le cluster n'est
     aujourd'hui **pas reproductible**. → à figer dans un `k8s/cilium-values.yaml`
     versionné + un script/Makefile d'install.
  2. **Version Cilium non figée** : la version déployée est `1.21.0-dev`
     (image `quay.io/cilium/cilium-ci:latest`), buildée depuis une archive de sources
     (`k8s/main.tar.gz`, ~94 Mo, désormais gitignorée). Un build CI `latest` n'est ni
     reproductible ni défendable en entretien. → repasser sur une **release stable
     épinglée** (chart `cilium/cilium --version X.Y.Z`), sauf besoin explicite d'une
     feature non publiée.
  3. **Mode de routage = VXLAN (tunnel)** — c'est le défaut Cilium, mais il est en
     tension avec l'objectif *network-native* : en tunnel, le trafic pod↔pod est
     encapsulé et la fabric ne voit que du VXLAN entre IP de nœuds ; elle ne route pas
     réellement les pods. Le BGP fonctionnerait quand même pour l'accès *externe → pod*,
     mais l'intérêt de la démo (la fabric route les pod CIDR nativement) tombe.
     → étudier `routingMode: native` + `autoDirectNodeRoutes` / annonce BGP des podCIDR.
- **Prochaine étape** :
  1. **Rendre l'install reproductible** : figer les values Cilium dans le repo,
     épingler une version stable, réinstaller depuis le fichier versionné.
  2. **Trancher tunnel vs native routing** et documenter le choix (c'est *la* décision
     d'archi de la phase 2 — savoir l'argumenter vaut plus que la config elle-même).
  3. Déployer un **workload de test** (2 pods sur 2 workers différents) et vérifier le
     pod↔pod inter-nœud — ça donne un point de comparaison *avant* BGP.
  4. Configurer le **BGP control plane Cilium** (`CiliumBGPClusterConfig`) : peering
     eBGP de chaque nœud avec **son** leaf, annonce du **pod CIDR**, puis d'un **pool
     LoadBalancer** ; valider côté fabric (`show bgp ipv4 unicast` sur leaf1/leaf2 et
     sur les spines, vérifier l'ECMP).
- **Décisions actées** : cluster = 1 control-plane + 2 workers ; seuls les **workers**
  sont câblés à la fabric (le control-plane reste sur le réseau kind `172.18.0.0/16`) ;
  `1 nœud = 1 leaf` confirmé et implémenté.

## 2026-07-24 — Phase 2 (install Cilium reproductible + passage en native routing)
- **Fait** :
  - **Dette #1 soldée — l'install est dans le repo** : création de `k8s/cilium-values.yaml`,
    commenté clé par clé (le *pourquoi*, pas le *quoi*). Plus aucune valeur passée en
    `--set` sur la ligne de commande.
  - **Dette #2 soldée — version épinglée** : abandon du chart `1.21.0-dev` /
    `quay.io/cilium/cilium-ci:latest` (buildé depuis sources) au profit de la release
    stable **1.19.6**. `k8s/main.tar.gz` (94 Mo) supprimé. Réinstall propre via
    `helm uninstall` puis réinstall (downgrade de chart majeur → repartir de zéro
    plutôt qu'un `upgrade` risqué côté CRD).
  - **Création d'un `Makefile`** à la racine : point d'entrée unique du projet
    (`fabric-up/down`, `cluster-up/down`, `cilium-install`, `cilium-status`).
    `CILIUM_VERSION ?= 1.19.6` vit désormais dans le repo et non dans l'historique bash.
    `helm upgrade --install` → cible idempotente, rejouable. `cilium-install` dépend de
    `cilium-repo` : sur une machine neuve, la commande marche sans prérequis manuel.
- **Décision d'archi tranchée — `routingMode: native`** (dette #3) :
  - **`routingMode: native`** : plus d'encapsulation, le paquet quitte le nœud avec
    l'IP du pod en source. En tunnel (défaut), la fabric n'aurait vu que du VXLAN entre
    IP de nœuds et n'aurait jamais routé les pod CIDR — l'objectif *network-native*
    tombait.
  - **`ipv4NativeRoutingCIDR: 10.244.0.0/16`** : périmètre où Cilium **désactive le
    masquerading**. Sans lui, le trafic pod↔pod inter-nœud sortirait SNAT en IP de nœud
    (`10.1.1.10`) et la fabric ne verrait jamais une IP de pod. Couvre les 3 podCIDR
    sans déborder (un `0.0.0.0/0` casserait la sortie internet). C'est une
    **affirmation**, pas une action : Cilium ne fait rien pour la rendre vraie, c'est
    le rôle du BGP.
  - **`autoDirectNodeRoutes: false`** : le point le plus important. Ce flag aurait
    installé une route directe vers le podCIDR de chaque autre nœud via son InternalIP.
    Or les 3 nœuds partagent le **bridge Docker de kind** (`172.18.0.0/16`) : la route
    aurait fonctionné, et le trafic pod↔pod serait passé par ce bridge de management
    en **court-circuitant totalement la fabric** (ni leaf, ni spine, ni ECMP). Ça aurait
    « marché » sans rien démontrer — un `ping` n'aurait rien révélé, seul un
    `traceroute` l'aurait vu. Désactivé délibérément pour laisser le trou que le BGP
    viendra combler.
  - **`bgpControlPlane.enabled: true`** activé dès maintenant pour éviter une 3ᵉ
    réinstallation.
- **Validé** :
  - Chart `cilium-1.19.6`, revision 1 (install propre), image
    `quay.io/cilium/cilium:v1.19.6@sha256:0df5b27…` — release épinglée **avec digest**,
    donc reproductible bit pour bit. 3/3 pods `cilium` Running.
  - `cilium-dbg status` → **`Routing: Network: Native`**.
  - **Le trou attendu est bien là** — table de routage de `worker`, avant/après :
    - avant (tunnel) : `10.244.0.0/24` et `10.244.2.0/24` via `cilium_host`, **`mtu 1450`**
      (= 1500 − 50 octets d'entête VXLAN, la signature du tunnel) ;
    - après (native) : ces deux routes ont **disparu**, `worker` ne connaît plus que son
      propre `10.244.1.0/24`. Les `mtu 1450` aussi → plus d'encapsulation.
  - `Masquerading: IPTables [IPv4: Enabled]` reste affiché : **normal**, le masquerade
    est actif pour la sortie internet, `ipv4NativeRoutingCIDR` en exempte les
    destinations en `10.244.0.0/16`. Les deux réglages cohabitent.
- **Attendu / pas un bug** : le pod↔pod **inter-nœud est cassé** à ce stade, faute de
  route vers les podCIDR distants. C'est l'effet voulu de `autoDirectNodeRoutes: false`.
- **Question ouverte identifiée pour le BGP** : la session BGP de Cilium partira de
  l'**InternalIP** du nœud (`172.18.0.3`), pas de son IP fabric (`10.1.1.10`), alors que
  leaf1 attend un voisin sur `10.1.1.0/24`. Piste retenue : **`CiliumBGPNodeConfigOverride`**
  (un objet par nœud) pour fixer l'adresse locale de session + le router-ID — ces valeurs
  étant spécifiques à chaque nœud, elles n'ont pas leur place dans des values Helm.
  Bénéfice induit : le **next-hop annoncé suit la source de session**, donc le podCIDR
  sera annoncé avec un next-hop que le leaf sait joindre en direct. Alternative écartée :
  forcer `--node-ip` sur kubelet — `eth1` est créée par containerlab *après* le démarrage
  du nœud kind, donc kubelet a déjà choisi `172.18.0.3` ; ordre de démarrage trop fragile.
- **Bloqué** : —
- **Prochaine étape** :
  1. Redéployer la fabric (`make fabric-up`) — elle n'est pas active actuellement, et
     les workers n'ont donc pas encore leur interface `eth1`.
  2. **Objectif B** : déployer 2 pods sur les 2 workers, constater l'échec du pod↔pod
     inter-nœud et savoir l'expliquer par la table de routage → point de comparaison
     *avant* BGP.
  3. Configurer le **BGP control plane** (`CiliumBGPClusterConfig` +
     `CiliumBGPNodeConfigOverride`) : peering eBGP de chaque nœud avec **son** leaf,
     annonce du pod CIDR, puis d'un pool LoadBalancer ; valider côté fabric
     (`show bgp ipv4 unicast` sur leaf1/leaf2 et les spines, vérifier l'ECMP).
- **Décisions actées** : `routingMode: native` + `autoDirectNodeRoutes: false` =
  la fabric doit apprendre les podCIDR par eBGP, aucun raccourci L2 toléré ;
  version Cilium épinglée dans le `Makefile` ; toute opération d'infra passe
  désormais par une cible `make`.

## 2026-07-28 (soirée) — Phase 2 (préparation du workload de test « avant BGP »)
Session courte, consacrée à l'**objectif B** : déployer 2 pods sur les 2 workers pour
constater l'échec du pod↔pod inter-nœud *avant* d'activer le BGP. Le workload n'est pas
encore déployé, mais deux contraintes d'environnement inattendues ont été identifiées
et documentées — c'est le vrai acquis de la soirée.

- **Fait** :
  - **Fabric redéployée** (`make fabric-up`) : joignabilité leaf → nœud kind revalidée
    (`leaf1 → 10.1.1.10`, `leaf2 → 10.1.2.10`).
  - **Manifest `k8s/netshoot-daemonset.yaml` écrit**. Choix du **DaemonSet** plutôt qu'un
    `Deployment` + `podAntiAffinity` ou 2 `Pod` bruts : garantit **un pod par nœud par
    construction**, sans nom de nœud codé en dur, et colle au design `1 nœud = 1 leaf`.
    Le taint `NoSchedule` posé par kind sur le control-plane suffit à l'en exclure —
    aucune `toleration`, donc les pods atterrissent sur les 2 workers seulement.
    `command: ["sleep","infinity"]` (l'entrypoint de netshoot rend la main → sinon
    `CrashLoopBackOff`). **Pas de `hostNetwork`** : le pod aurait pris l'IP du nœud
    (`172.18.0.x`) au lieu d'une IP de pod, et le test aurait perdu tout son sens.
  - **Cible `netshoot-load` ajoutée au `Makefile`** (+ `workload-up` / `workload-down`).

- **Découverte 1 — les nœuds attachés à la fabric n'ont plus d'egress internet.**
  Containerlab **remplace la route par défaut** du nœud : `default via 10.1.1.1 dev eth1`,
  il ne reste sur `eth0` qu'une route de lien vers `172.18.0.0/16`. Le trafic sortant part
  donc vers `leaf1`, et la fabric est un monde clos (aucun NAT vers l'extérieur).
  Preuve : `curl https://registry-1.docker.io/v2/` depuis `worker` → **exit 124 (timeout)**.
  Conséquence : **kubelet ne peut plus pull aucune image** sur ces nœuds ⇒ toute image doit
  être **préchargée** via `kind load`, et le manifest doit porter `imagePullPolicy: IfNotPresent`
  (avec `Always`, kubelet retenterait un pull réseau et échouerait *même image présente*).
  Ce n'est pas un bug mais un effet de bord assumé du design — c'est exactement la contrainte
  d'un vrai DC en underlay pur. Explique rétroactivement le `image.pullPolicy` bricolé en
  `--set` à l'époque de l'install Cilium.

- **Découverte 2 — `kind load docker-image` est cassé par le containerd image store.**
  `docker info` → `driver-type: io.containerd.snapshotter.v1`. Avec ce backend, Docker garde
  l'**index multi-plateforme** complet de l'image alors qu'il n'a téléchargé que la variante
  `linux/amd64`. Or kind importe avec `ctr images import --all-platforms`, qui tente de
  résoudre *toutes* les entrées de l'index et échoue sur le manifeste arm64 absent :
  `ctr: content digest sha256:f460dc5e…: not found`. Rien à voir avec le réseau ni le cluster.
  → **Contournement retenu** : `docker save --platform linux/amd64 -o <tar>` puis
  `kind load image-archive`, c.-à-d. une archive **mono-plateforme** ne contenant que ce
  qu'on possède réellement. Fait à la main ce soir : **image chargée avec succès sur les
  3 nœuds**.

- **Bloqué / à finir (reprise ici) — la cible `netshoot-load` ne marche pas encore** :
  1. `TAR=$$(mktemp …): \` — un **`:` au lieu d'un `;`**. Une fois les lignes recollées par
     le `\`, le shell lit `TAR=… docker save …` : c'est la forme *affectation d'environnement
     pour une seule commande*, donc `TAR` disparaît ensuite et `kind load` / `rm` reçoivent
     une variable **vide**.
  2. `mktemp /tmp/netshoot.tar` → `too few X's in template` (exit 1) : `mktemp` exige au moins
     3 `X` consécutifs. Utiliser `…XXXXXX` + `--suffix=.tar` (cf. `man mktemp`).
  3. **Enchaîner en `&&` (ou `set -e`) plutôt qu'en `;`** : avec des `;`, un échec de `mktemp`
     ou de `docker save` n'interrompt rien, et Make renvoie le code du **dernier** `rm -f`
     (qui réussit toujours) → la cible dirait « OK » sans avoir rien chargé.
  4. **Ajouter le commentaire du *pourquoi*** au-dessus de la cible (les 2 découvertes
     ci-dessus). Sans lui, la cible passe pour une complication gratuite face au
     `kind load docker-image` d'une ligne, et quelqu'un la « simplifiera ».
  5. **Trancher `workload-up: netshoot-load`** — dépendance ou pas ? Sans elle, itérations
     rapides sur le YAML ; mais sur une machine neuve `make workload-up` donne des
     `ImagePullBackOff`. Décider **et commenter le choix**.
  6. `k8s/netshoot-daemonset.yaml` : **le namespace `netlab` n'est pas déclaré** alors que le
     DaemonSet le référence → `apply` échouera. Ajouter l'objet `Namespace` **dans le même
     fichier**, avant le DaemonSet, séparé par `---` (appliqué dans l'ordre du document ;
     et `kubectl delete -f` nettoie tout par garbage collection).
  7. Cosmétique : tabulation parasite dans `CILIUM_VERSION	?=`, alignement des variables,
     espace manquant dans le séparateur `# --- Déploiement … -----`.

- **Prochaine étape** :
  1. Finir `netshoot-load` (points 1→5) et déclarer le namespace (point 6), puis
     `make workload-up`.
  2. **Objectif B — la séquence de mesure**, dans cet ordre :
     a. `kubectl get pods -n netlab -o wide` → vérifier que les IP tombent bien dans
        `10.244.1.x` (worker) et `10.244.2.x` (worker2).
     b. ping **intra-nœud** → doit **réussir** (contrôle négatif : prouve que le CNI n'est
        pas cassé — c'est l'étape que tout le monde saute, et c'est elle qui transforme
        « mon cluster est cassé » en « j'ai laissé un trou délibéré »).
     c. ping **pod worker → pod worker2** → doit **échouer**.
     d. `docker exec l3bgp-cluster-worker ip route` → montrer l'absence de route vers
        `10.244.2.0/24`. **Garder ces sorties** : c'est le « avant » de la démo.
  3. Lire la doc BGP Cilium et noter *quel objet porte quoi* (`CiliumBGPClusterConfig`,
     `CiliumBGPPeerConfig`, `CiliumBGPNodeConfigOverride`) : ASN, adresse du peer, adresse
     locale de session, ce qu'on annonce.
  4. Puis configurer le peering eBGP nœud ↔ son leaf et annoncer les podCIDR.

- **À savoir pour le BGP (mise à jour d'une note du 24/07)** : les InternalIP des workers
  ont **changé de place** au redémarrage (`worker` est passé de `172.18.0.3` à `172.18.0.4`,
  et inversement pour `worker2`) — le bridge Docker réattribue selon l'ordre de démarrage.
  Ces adresses sont donc **instables et inutilisables comme identité BGP durable** :
  argument supplémentaire en faveur de `CiliumBGPNodeConfigOverride`, qui épinglera l'IP
  fabric (`10.1.1.10` / `10.1.2.10`), stable car versionnée dans la topologie clab.

- **Décisions actées** : workload de test = **DaemonSet** netshoot (`v0.16`, tag explicite,
  jamais `latest`) ; images **préchargées** via archive mono-plateforme, jamais pullées
  depuis les nœuds ; namespace dédié `netlab` déclaré **dans le manifest** et non créé
  en impératif.

## 2026-08-01 — Phase 2 (outillage : Makefile fiabilisé, préchargement d'images, réorg)
Session dense côté **infrastructure du lab**, pas côté BGP : le workload de test tourne
enfin correctement, et surtout le lab se remonte **de zéro en une commande**. Une panne
d'installation Cilium a révélé un défaut de conception réel (dépendance d'ordre implicite)
qui est maintenant corrigé.

> ⚠️ **À RELIRE À TÊTE REPOSÉE** — cette session a été menée en grande partie avec
> l'assistance de Claude Code, et plusieurs fichiers ont été écrits par lui. Je ne
> maîtrise pas encore tout ce qui suit. Points à reprendre et à savoir réexpliquer
> **avant l'entretien** (liste en fin d'entrée).

- **Fait — `netshoot-load` réparé puis remplacé** :
  - Les 4 bugs listés le 28/07 étaient réels : `:` au lieu de `;` (le shell lisait
    `TAR=… docker save …`, c.-à-d. une affectation d'environnement pour une seule
    commande → `TAR` vide ensuite) ; `mktemp` sans 3 `X` consécutifs ; chaînage en `;`
    masquant les échecs derrière le code de retour du `rm -f` final ; `docker pull`
    inconditionnel. Corrigés, puis la cible a été **généralisée** (voir plus bas).
  - Leçon Make retenue : un commentaire en **colonne 0** est un commentaire *Make*
    (invisible) ; indenté par une tabulation, il devient un commentaire *shell* et
    s'affiche à chaque exécution. Vérifiable avec `make -n`.

- **Fait — manifest du workload complété** (`netshoot-daemonset.yaml`) :
  - `Namespace netlab` **déclaré dans le fichier**, en premier document (`apply` traite
    les documents dans l'ordre). Le `apply` a d'ailleurs émis un warning
    `missing kubectl.kubernetes.io/last-applied-configuration` : la trace de la création
    impérative précédente. Dérive soldée.
  - **Deux DaemonSets** `netshoot-a` / `netshoot-b` au lieu d'un seul. Raison : un
    DaemonSet donne **un pod par nœud**, donc aucune paire intra-nœud — le contrôle
    négatif de l'objectif B était structurellement impossible. Les deux `selector`
    portent `app: netshoot` **plus** un label `pair: a|b` : avec `app` seul des deux
    côtés, chaque DaemonSet adopterait les pods de l'autre. Le `selector` d'un
    DaemonSet est **immuable** → une erreur de labels impose `delete` puis `apply`.
  - Résultat : **4 pods Running**, 2 par worker (`10.244.1.133`/`10.244.1.190` sur
    worker, `10.244.2.133`/`10.244.2.5` sur worker2).

- **Fait — réorganisation de `k8s/`** selon le critère *« qui applique le fichier ? »* :
  - `k8s/bootstrap/` : `kind-config.yaml`, `cilium-values.yaml`, `images.txt` — ce qui
    **crée** le cluster. Ne pourra **jamais** être géré par ArgoCD (ça existe avant le
    cluster, ou avant le CNI dont Argo dépend pour tourner).
  - `k8s/manifests/` : objets K8s appliqués par `kubectl` aujourd'hui, par **ArgoCD**
    en phase 3. C'est cette frontière qui rendra l'app-of-apps possible sans
    retoucher l'arborescence.
  - Les variables de chemin en tête de Makefile ont absorbé le déplacement en 3 lignes.

- **PANNE — `cilium-install` échoue une fois la fabric allumée** :
  - Symptôme : `ImagePullBackOff` sur **tous** les pods Cilium de `worker`/`worker2`,
    alors que ceux du control-plane tournent. `dial tcp 32.193.160.199:443: i/o timeout`
    vers quay.io.
  - Cause : c'est la **Découverte 1 du 28/07 appliquée à Cilium lui-même**. `fabric-up`
    fait remplacer la route par défaut des workers par `default via 10.1.1.1 dev eth1` ;
    la fabric n'a aucun NAT, donc plus d'egress, donc kubelet ne pull plus rien.
    Le 24/07 ça passait uniquement parce que la fabric était **éteinte** au moment de
    l'install. Le vrai défaut : une **dépendance d'ordre implicite**, ni documentée ni
    appliquée par le Makefile.
  - À noter : `fabric-down` **ne restaure pas** la route par défaut d'origine (le nœud
    se retrouve sans `default` du tout) — on ne peut donc pas s'en sortir en éteignant
    la fabric, il faudrait recréer le cluster.

- **Investigation — pourquoi une image épinglée par digest ne peut PAS être préchargée** :
  - `docker save` d'une référence à digest produit une archive **sans nom**
    (`"RepoTags": null`) ; `kind load` l'importe (exit 0, **aucun message**) mais
    containerd l'enregistre sous un nom inventé : `import-2026-07-31@sha256:8bc32d97…`.
    Kubelet, qui réclame `quay.io/cilium/cilium:v1.19.6@sha256:0df5b27…`, ne l'y
    retrouve jamais et repart en pull réseau.
  - Racine : c'est le prolongement de la Découverte 2. `docker save --platform` produit
    une archive **mono-plateforme**, dont le digest de manifeste **diffère** par
    construction de celui de l'index multi-plateforme épinglé.
  - **Parade validée expérimentalement** : `docker pull` **par digest** (contenu vérifié
    à l'octet près) → `docker tag` en `nom:tag` → `docker save` du **tag** → l'archive
    porte `"RepoTags":["quay.io/cilium/operator-generic:v1.19.6"]` et containerd
    l'enregistre sous ce nom. **L'épinglage ne disparaît pas : il se déplace** du
    manifeste Kubernetes vers l'étape de préchargement.
  - Corollaire obligatoire : le chart doit cesser d'émettre des références à digest,
    sinon kubelet demande un nom absent → `useDigest: false` sur `image`,
    `operator.image` et `envoy.image` dans `cilium-values.yaml`.

- **Fait — `images-preload`, cible générique** (remplace `netshoot-load`) :
  - Liste des images dans **`k8s/bootstrap/images.txt`** (4 images : cilium,
    operator-generic, cilium-envoy, netshoot), épinglées par digest, avec le
    raisonnement en tête de fichier et la commande `helm template … | grep image:`
    pour retrouver les digests au prochain bump de version. Sortir la liste du
    Makefile prépare la phase 4 (Prometheus, Grafana).
  - La cible **saute toute image déjà présente** sur les 3 nœuds : **42 s** à froid,
    **0,66 s** en régime établi. Bug attrapé à l'usage : containerd normalise
    `nicolaka/netshoot:v0.16` en `docker.io/nicolaka/netshoot:v0.16`, donc la
    comparaison exacte ne matchait jamais et netshoot était rechargé à chaque appel.
  - `cilium-install` et `workload-up` en **dépendent** → l'installation est désormais
    **insensible à l'ordre** des cibles.

- **Fait — cibles `lab-up` / `lab-down`** : l'ordre `cluster-up → fabric-up →
  cilium-install → workload-up` est maintenant **encodé** et non plus seulement
  documenté (les conteneurs kind doivent exister avant clab, qui les référence par
  leur nom). C'est la correction du défaut de fond révélé par la panne.

- **Validé** : 3 nœuds `Ready`, `cilium-status` → image `quay.io/cilium/cilium:v1.19.6`
  (release, pas `:latest`), `Routing: Network: Native`, 4 pods netshoot `Running`.

- **Fait — squelettes BGP créés** (`k8s/manifests/bgp/`, **vides, à remplir moi-même**) :
  `bgp-common.yaml` (PeerConfig + Advertisement, communs aux deux peerings),
  `bgp-leaf1.yaml` et `bgp-leaf2.yaml` (un ClusterConfig + un NodeConfigOverride chacun).

- **Décision d'archi — il faut DEUX `CiliumBGPClusterConfig`** :
  `peerAddress` vit dans le `ClusterConfig` et diffère d'un nœud à l'autre
  (`10.1.1.1` vs `10.1.2.1`) ; or le `nodeSelector` est au niveau du `spec` et
  s'applique à **toutes** les `bgpInstances`. Deux instances dans un seul objet
  feraient donc que chaque nœud tenterait de joindre le leaf de l'autre, sans route
  pour y aller. Et `CiliumBGPNodeConfigOverride` **ne surcharge pas** `peerAddress`
  (seulement `routerID`, adresse locale de session, ports). D'où : deux ClusterConfig
  à `nodeSelector` disjoints, mais **un seul** PeerConfig et un seul Advertisement,
  référencés par les deux.

- **Décision actée — un ASN par nœud** (et non un ASN unique pour le cluster).
  Justification RFC 7938 (un ASN privé par équipement) — mais l'argument **décisif**
  est ailleurs : avec un ASN partagé par les deux workers, le podCIDR de `worker`
  annoncé à leaf1 remonterait aux spines puis redescendrait vers `worker2`, qui le
  **rejetterait** — son propre ASN figurant dans l'AS-path, la prévention de boucle
  eBGP le supprime. Le pod↔pod inter-nœud ne fonctionnerait pas, sauf à bricoler un
  `allowas-in`. Un ASN par nœud supprime le problème à la racine. *(À vérifier
  moi-même en observant l'AS-path sur spine1 une fois le peering monté.)*

- **Bloqué** : —
- **Prochaine étape** :
  1. **Relire et comprendre** les fichiers écrits cette session (liste ci-dessous).
  2. Poser le label `fabric.leaf: leaf1|leaf2` dans `kind-config.yaml` (champ `labels`
     par entrée de `nodes` ; l'ordre des entrées détermine le nom du nœud). Attention :
     les labels sont posés à l'**enregistrement** du nœud → recréer le cluster
     (`make lab-down && make lab-up`), ce qui validera la chaîne au passage.
  3. **Objectif B** — la séquence de mesure « avant BGP », enfin possible avec les
     4 pods : (a) vérifier les IP, (b) ping **intra-nœud** → doit réussir (contrôle
     négatif), (c) ping **inter-nœud** → doit échouer, (d) `ip route` sur worker →
     absence de `10.244.2.0/24`. **Garder les sorties dans `docs/`**, c'est le « avant ».
  4. Écrire `bgp-common.yaml` puis `bgp-leaf1.yaml` **seul** ; monter et valider ce
     premier peering (`show bgp summary` sur leaf1) avant d'écrire `bgp-leaf2.yaml`.
     Ne pas oublier le côté FRR : `clab/configs/leaf1/frr.conf` ne connaît pas encore
     ce voisin.

- **À RELIRE / REFAIRE MOI-MÊME (dette de compréhension)** :
  1. `Makefile`, cible `images-preload` : la boucle `while read` en shell, pourquoi
     tout le corps est **un seul** shell (les `\`), le rôle de `set -e`, et le `$$`
     de Make. Objectif : savoir la réécrire de mémoire.
  2. Le raisonnement **digest vs tag** en entier — c'est le point le plus subtil de la
     session et **le compromis que je devrai défendre en entretien** : mes manifestes
     ne portent plus de digest, l'épinglage vit dans `images.txt`. Savoir dire pourquoi
     (les nœuds n'atteignent aucun registre, donc la reproductibilité s'ancre au
     préchargement).
  3. `k8s/manifests/workloads/netshoot-daemonset.yaml` : pourquoi deux DaemonSets,
     pourquoi les labels doivent être disjoints, pourquoi pas de `hostNetwork`.
  4. La distinction `k8s/bootstrap/` vs `k8s/manifests/` et son lien avec ArgoCD.
  5. Refaire **à la main** le diagnostic de la panne : `kubectl describe pod` →
     `docker exec <worker> ip route` → conclusion. C'est un exercice de dépannage
     typique en entretien.
