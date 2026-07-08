# netnative-k8s — un cluster Kubernetes *network-native*

Projet portfolio : un cluster Kubernetes intégré nativement à une **fabric
datacenter leaf-spine en eBGP**, dont le CNI (Cilium) **peere en BGP** avec les
ToR, le tout **piloté en GitOps**. Objectif : démontrer des compétences
cloud/DevOps avec une forte corde réseau.

## Le pitch en une phrase

> J'ai monté une fabric datacenter leaf-spine en BGP, j'y ai raccordé un cluster
> Kubernetes dont le CNI peere en BGP avec les ToR — de sorte que les IP de pods
> et de LoadBalancer sont routées dans la fabric — et tout est déployé et
> réconcilié en GitOps.

## Architecture cible

```
              +-----------+        +-----------+
              |  spine1    |        |  spine2   |     underlay eBGP (RFC 7938)
              | AS 65001   |        | AS 65002  |     un ASN par équipement
              +-----+-----+        +-----+------+
                   / \                  / \
                  /   \                /   \
                 /     \              /     \
        +-------+--+   +-+----------+-+   +--+------+
        |  leaf1     |                |  leaf2      |
        | AS 65011   |                | AS 65012    |
        +-----+------+                +------+------+
              |                              |
        [ nœuds K8s ]                  [ nœuds K8s ]   (phase 2 : kind + Cilium BGP)
```

## Roadmap

| Phase | Contenu | Statut |
|-------|---------|--------|
| 1 | Fabric leaf-spine FRR, underlay eBGP (containerlab) | en cours |
| 2 | Cluster kind + Cilium, peering BGP nœud↔leaf, LoadBalancer | à venir |
| 3 | GitOps (ArgoCD), IaC (Ansible/Terraform) | à venir |
| 4 | Observabilité (Prometheus/Grafana/Hubble) + CI (GitHub Actions) | à venir |
| 5 | Scénarios de démo + polish (README, article) | à venir |
| Bonus | Edge MPLS L3VPN : cluster joignable depuis un site distant | à venir |

## Structure du repo

```
netnative-k8s/
├── README.md            # ce fichier
├── PROGRESS.md          # journal de bord daté (source de vérité du suivi)
├── CLAUDE.md            # contexte pour Claude Code
├── clab/                # topologies containerlab + configs FRR
│   ├── leaf-spine.clab.yml
│   └── configs/
│       ├── daemons              # daemons FRR (partagé)
│       ├── spine1/frr.conf
│       ├── spine2/frr.conf
│       ├── leaf1/frr.conf
│       └── leaf2/frr.conf
├── k8s/                 # (phase 2) manifests, valeurs Helm
├── gitops/              # (phase 3) apps ArgoCD
├── iac/                 # (phase 3) Ansible / Terraform
├── observability/       # (phase 4) Prometheus, Grafana, dashboards
└── ci/                  # (phase 4) workflows GitHub Actions
```

## Lab — prérequis

- VM Linux (ici Debian 13 Trixie), Docker + containerlab installés
- ~20 Go RAM / 4 vCPU alloués à la VM

## Lancer la phase 1

```bash
cd clab
sudo clab deploy -t leaf-spine.clab.yml
```

Voir `PROGRESS.md` pour l'état courant et les commandes de validation.