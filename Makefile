# Makefile — point d'entrée unique du projet.
# Tout ce qui déploie ou modifie l'infra passe par une cible d'ici, jamais par une
# commande tapée à la main : c'est ce qui rend le lab reproductible.
#
# ATTENTION : les commandes sous chaque cible sont indentées par une TABULATION.

# `?=` : valeur par défaut, surchargeable sans éditer ce fichier.
#   ex. `make cilium-install CILIUM_VERSION=1.19.5`
CILIUM_VERSION	?= 1.19.6
NETSHOOT_IMAGE   ?= nicolaka/netshoot:v0.16

DOCKER_ARCH    := linux/amd64

CLAB_TOPO      := clab/leaf-spine.clab.yml
KIND_CONFIG    := k8s/config.yaml
KIND_CLUSTER   := l3bgp-cluster
CILIUM_VALUES  := k8s/cilium-values.yaml
NETSHOOT_DAEMON := k8s/netshoot-daemonset.yaml

# Cibles qui ne produisent pas de fichier portant leur nom.
.PHONY: help fabric-up fabric-down cluster-up cluster-down \
        cilium-repo cilium-install cilium-status netshoot-load workload-up workload-down

# Cible par défaut (la première du fichier) : `make` seul affiche l'aide.
help:
	@echo "Cibles disponibles :"
	@echo "  fabric-up       - deploie la fabric leaf-spine (containerlab)"
	@echo "  fabric-down     - detruit la fabric"
	@echo "  cluster-up      - cree le cluster kind (sans CNI)"
	@echo "  cluster-down    - supprime le cluster kind"
	@echo "  cilium-install  - installe/met a jour Cilium (version $(CILIUM_VERSION))"
	@echo "  cilium-status   - etat de Cilium et mode de routage effectif"
	@echo "  netshoot-load   - charge l'image netshoot"
	@echo "  workload-up     - deploye le DaemonSet netshoot sur le cluster"
	@echo "  workload-down   - supprime le DaemonSet netshoot du cluster"

# --- Fabric (phase 1) -------------------------------------------------------
# containerlab manipule les netns et les veth : root requis.
fabric-up:
	sudo containerlab deploy -t $(CLAB_TOPO)

fabric-down:
	sudo containerlab destroy -t $(CLAB_TOPO)

# --- Cluster kind (phase 2) -------------------------------------------------
# Le cluster doit exister AVANT `fabric-up` : la topologie clab reference les
# conteneurs kind par leur nom pour leur brancher un lien vers leur leaf.
cluster-up:
	kind create cluster --config $(KIND_CONFIG)

cluster-down:
	kind delete cluster --name $(KIND_CLUSTER)

# --- Cilium -----------------------------------------------------------------
cilium-repo:
	helm repo add cilium https://helm.cilium.io/ 2>/dev/null || true
	helm repo update cilium

# `upgrade --install` est idempotent : rejouable sans erreur si deja installe.
# La version est EPINGLEE (--version) : pas de derive silencieuse vers une
# nouvelle release entre deux `make`.
cilium-install: cilium-repo
	helm upgrade --install cilium cilium/cilium \
	  --version $(CILIUM_VERSION) \
	  --namespace kube-system \
	  --values $(CILIUM_VALUES)
	kubectl -n kube-system rollout status ds/cilium --timeout=180s

cilium-status:
	@echo "--- image deployee (doit etre une release, pas :latest) ---"
	@kubectl -n kube-system get ds cilium \
	  -o jsonpath='{.spec.template.spec.containers[0].image}'; echo
	@echo "--- mode de routage effectif (attendu : Native) ---"
	@kubectl -n kube-system exec ds/cilium -- cilium-dbg status \
	  | grep -Ei 'routing|masquerad'

# --- Déploiement container sur le cluster--------------------------------------

netshoot-load:
	@echo "--- chargement de l'image $(NETSHOOT_IMAGE) dans le cluster kind ---"
	docker pull $(NETSHOOT_IMAGE)
	TAR=$$(mktemp /tmp/netshoot.tar): \
	docker save --platform $(DOCKER_ARCH) \
	$(NETSHOOT_IMAGE) -o $$TAR; \
	kind load image-archive --name $(KIND_CLUSTER) $$TAR; \
	rm -f $$TAR

workload-up:
	kubectl apply -f $(NETSHOOT_DAEMON)

workload-down:
	kubectl delete -f $(NETSHOOT_DAEMON)
