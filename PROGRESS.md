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