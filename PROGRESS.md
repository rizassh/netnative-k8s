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
