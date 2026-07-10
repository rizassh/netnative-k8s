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
