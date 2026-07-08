# Contexte projet (pour Claude Code)

## Ce qu'est ce projet
Projet portfolio d'un étudiant en réseaux/télécoms visant un poste **cloud/DevOps
à forte corde réseau**. On construit un cluster Kubernetes *network-native* :
- Fabric datacenter **leaf-spine** (2 spines + 2 leaves) en **underlay eBGP** (RFC 7938),
  simulée avec **containerlab + FRR**.
- (Phase 2) Cluster **kind** + **Cilium** dont le control plane BGP **peere avec les leaves** ;
  pod CIDR et pool LoadBalancer annoncés dans la fabric.
- (Phase 3) **GitOps** avec ArgoCD (app-of-apps), **IaC** Ansible/Terraform.
- (Phase 4) Observabilité **Prometheus/Grafana/Hubble**, CI **GitHub Actions**.
- (Bonus) Edge **MPLS L3VPN** : cluster joignable depuis un site distant.

L'état d'avancement réel est dans `PROGRESS.md` — lis-le en premier.

## Conventions
- Une seule source de vérité : **ce repo**. Pas de config qui vit hors du repo.
- Tout changement d'infra passe par un fichier versionné (topologie, manifest, playbook).
- Adressage underlay en /31, loopbacks en 10.255.0.0/24, ASN privés (un par équipement).
- Commits courts et fréquents, un message clair par étape.

## Garde-fous (important)
- Ce projet doit démontrer **mes** compétences en entretien. Quand tu m'aides à
  débugger, **explique le pourquoi**, ne te contente pas de corriger en silence.
- Tu ne dois pas me donner toutes les configurations, fichiers, lignes de code sans explication. 
- Mon but principal est d'apprendre, donne moi des objectifs à atteindre.
- Ne modifie pas de fichier sans me dire ce que tu changes et pourquoi.
- Privilégie des configs lisibles et pédagogiques à des one-liners obscurs.

## Environnement
- VM Debian 13 (Trixie), Docker + containerlab. ~20 Go RAM / 4 vCPU.
- Édition depuis un Mac via VS Code Remote-SSH ; exécution et git dans la VM.