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
