# Makefile — point d'entrée unique du projet.
# Tout ce qui déploie ou modifie l'infra passe par une cible d'ici, jamais par une
# commande tapée à la main : c'est ce qui rend le lab reproductible.
#
# ATTENTION : les commandes sous chaque cible sont indentées par une TABULATION.

# `?=` : valeur par défaut, surchargeable sans éditer ce fichier.
#   ex. `make cilium-install CILIUM_VERSION=1.19.5`
CILIUM_VERSION  ?= 1.19.6

# `:=` : valeur figee, non surchargeable — ce sont des constantes du lab.
DOCKER_ARCH     := linux/amd64

CLAB_TOPO       := clab/leaf-spine.clab.yml
# k8s/bootstrap/ : ce qui cree le cluster (kind, Helm) — jamais gere par ArgoCD.
# k8s/manifests/ : objets K8s appliques par kubectl aujourd'hui, par ArgoCD demain.
KIND_CONFIG     := k8s/bootstrap/kind-config.yaml
KIND_CLUSTER    := l3bgp-cluster
CILIUM_VALUES   := k8s/bootstrap/cilium-values.yaml
IMAGES_LIST     := k8s/bootstrap/images.txt
NETSHOOT_DAEMON := k8s/manifests/workloads/netshoot-daemonset.yaml

# Cibles qui ne produisent pas de fichier portant leur nom.
.PHONY: help lab-up lab-down fabric-up fabric-down cluster-up cluster-down \
        cilium-repo cilium-install cilium-status images-preload workload-up workload-down

# Cible par défaut (la première du fichier) : `make` seul affiche l'aide.
help:
	@echo "Cibles disponibles :"
	@echo "  lab-up          - monte tout le lab de zero, dans l'ordre"
	@echo "  lab-down        - detruit tout le lab"
	@echo "  fabric-up       - deploie la fabric leaf-spine (containerlab)"
	@echo "  fabric-down     - detruit la fabric"
	@echo "  cluster-up      - cree le cluster kind (sans CNI)"
	@echo "  cluster-down    - supprime le cluster kind"
	@echo "  images-preload  - precharge les images de $(IMAGES_LIST) dans les noeuds"
	@echo "  cilium-install  - installe/met a jour Cilium (version $(CILIUM_VERSION))"
	@echo "  cilium-status   - etat de Cilium et mode de routage effectif"
	@echo "  workload-up     - deploye le DaemonSet netshoot sur le cluster"
	@echo "  workload-down   - supprime le DaemonSet netshoot du cluster"

# --- Lab complet -------------------------------------------------------------
# L'ORDRE compte et n'est pas devinable — d'ou cette cible, qui l'encode :
#   1. cluster-up : les conteneurs kind doivent EXISTER avant clab, qui les
#      reference par leur nom pour leur brancher un lien vers leur leaf ;
#   2. fabric-up  : cablage + underlay eBGP ;
#   3. cilium-install / workload-up : insensibles a l'ordre grace au
#      prechargement des images (sans lui, ils echouent une fois la fabric
#      allumee, puisque les workers perdent leur egress).
# Make execute les prerequis de gauche a droite — ne pas lancer avec `-j`.
lab-up: cluster-up fabric-up cilium-install workload-up
	@echo "--- lab complet ---"

lab-down: workload-down fabric-down cluster-down

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
# Depend de `images-preload` : sans lui, l'install echoue des que la fabric est
# allumee (les workers n'ont plus d'egress, cf. la cible en question). C'est ce
# prechargement qui rend `cilium-install` insensible a l'ordre des cibles.
cilium-install: cilium-repo images-preload
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

# --- Prechargement des images ------------------------------------------------
#
# POURQUOI ce detour au lieu du `kind load docker-image` d'une seule ligne.
# Trois contraintes d'environnement — ne pas "simplifier" cette cible :
#
# 1. Les noeuds attaches a la fabric n'ont PLUS d'acces internet. containerlab
#    remplace leur route par defaut (`default via 10.1.1.1 dev eth1`) : tout le
#    trafic sortant part vers leaf1, et la fabric est un monde clos (aucun NAT
#    vers l'exterieur). kubelet ne peut donc plus pull aucune image sur ces
#    noeuds => TOUTE image du cluster doit etre prechargee, y compris celles de
#    Cilium lui-meme, et les manifests portent `imagePullPolicy: IfNotPresent`
#    (avec `Always`, kubelet retenterait un pull reseau et echouerait *meme image
#    deja presente*). Ce n'est pas un bug : c'est la contrainte d'un vrai DC en
#    underlay pur.
#
# 2. `kind load docker-image` est casse par le containerd image store de Docker
#    (`docker info` -> driver-type io.containerd.snapshotter.v1). Avec ce backend
#    Docker conserve l'index multi-plateforme complet de l'image alors qu'il n'a
#    telecharge que la variante linux/amd64. Or kind importe avec
#    `ctr images import --all-platforms`, qui tente de resoudre *toutes* les
#    entrees de l'index et echoue sur le manifeste arm64 absent :
#      ctr: content digest sha256:f460dc5e...: not found
#    => archive MONO-PLATEFORME (`docker save --platform`) + `kind load image-archive`.
#
# 3. Une image epinglee PAR DIGEST ne peut pas etre prechargee : `docker save`
#    d'une reference a digest produit une archive sans nom ("RepoTags": null),
#    que containerd enregistre sous `import-<date>@sha256:...`. Kubelet ne l'y
#    retrouve jamais. => on pull par digest (contenu verifie a l'octet pres) puis
#    on RETAGUE en `nom:tag` avant de sauvegarder. Corollaire : le chart Cilium
#    doit emettre des refs sans digest (`useDigest: false` dans les values).
#
# La liste des images vit dans $(IMAGES_LIST), pas ici : elle grossira avec les
# phases suivantes (Prometheus, Grafana...) et n'a pas a polluer le Makefile.
images-preload:
	@echo "--- prechargement des images dans $(KIND_CLUSTER) ---"
# Tout le corps est UN seul shell (Make en lance un par ligne de recette, d'ou les
# `\` de continuation) : c'est necessaire pour que la boucle et ses variables vivent.
# `$$` = un `$` litteral transmis au shell, Make consommant le premier.
# `set -e` : la cible echoue des la premiere commande en erreur. Sans lui, un
# `docker save` rate serait masque par le `rm -f` final (qui reussit toujours) et
# Make annoncerait "OK" sans avoir rien charge.
	@set -e; \
	while read -r REF; do \
	  case "$$REF" in ''|'#'*) continue ;; esac; \
	  TAG=$${REF%@*}; \
	  MISSING=0; \
	  for NODE in $$(kind get nodes --name $(KIND_CLUSTER)); do \
	    docker exec $$NODE ctr -n k8s.io images ls -q 2>/dev/null \
	      | grep -qE "(^|/)$${TAG}$$" || MISSING=1; \
	  done; \
	  if [ $$MISSING -eq 0 ]; then echo "  = deja present : $$TAG"; continue; fi; \
	  echo "  + chargement  : $$TAG"; \
	  docker image inspect "$$REF" >/dev/null 2>&1 \
	    || docker pull --platform $(DOCKER_ARCH) "$$REF" >/dev/null; \
	  docker tag "$$REF" "$$TAG"; \
	  TAR=$$(mktemp --suffix=.tar /tmp/kindimg.XXXXXX); \
	  docker save --platform $(DOCKER_ARCH) -o "$$TAR" "$$TAG"; \
	  kind load image-archive --name $(KIND_CLUSTER) "$$TAR"; \
	  rm -f "$$TAR"; \
	done < $(IMAGES_LIST)

# --- Deploiement du workload -------------------------------------------------
# Depend de `images-preload` : sur une machine neuve, un `kubectl apply` seul
# donnerait des ImagePullBackOff (cf. contrainte 1), et le lab ne serait pas
# reproductible d'une commande. Le cout est faible en regime etabli : la cible
# saute toute image deja presente dans containerd sur les 3 noeuds.
workload-up: images-preload
	kubectl apply -f $(NETSHOOT_DAEMON)

# `delete -f` supprime tous les objets du fichier, dont le Namespace : le reste
# part par garbage collection.
workload-down:
	kubectl delete -f $(NETSHOOT_DAEMON)
