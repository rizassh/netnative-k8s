# Après BGP — le podCIDR annoncé dans la fabric

Miroir de `avant-bgp.md`. Même lab, même workload, mais les nœuds kind peerent
maintenant en eBGP avec les leaves. À lire dans l'ordre : les pings montrent *que*
ça marche, les sections BGP montrent *pourquoi et par où*.

> Les IP de pods diffèrent de `avant-bgp.md` : les pods ont redémarré depuis
> (le lab a été redéployé). La démonstration est inchangée.
>
> | Pod                | IP             | Nœud                    |
> |--------------------|----------------|-------------------------|
> | `netshoot-a-pbm7w` | `10.244.1.68`  | `l3bgp-cluster-worker`  |
> | `netshoot-b-rwnx6` | `10.244.1.107` | `l3bgp-cluster-worker`  |
> | `netshoot-a-948fd` | `10.244.2.167` | `l3bgp-cluster-worker2` |
> | `netshoot-b-gdmf7` | `10.244.2.51`  | `l3bgp-cluster-worker2` |

---

## 1. Les pings passent — et le TTL trahit le chemin

### Intra-nœud (deux pods du même worker)

```
$ kubectl exec -n netlab netshoot-a-pbm7w -- ping -c3 10.244.1.107
64 bytes from 10.244.1.107: icmp_seq=1 ttl=63 time=0.065 ms
64 bytes from 10.244.1.107: icmp_seq=2 ttl=63 time=0.037 ms
64 bytes from 10.244.1.107: icmp_seq=3 ttl=63 time=0.034 ms
```

### Inter-nœud (le ping qui échouait dans `avant-bgp.md`)

```
$ kubectl exec -n netlab netshoot-a-pbm7w -- ping -c3 10.244.2.167
64 bytes from 10.244.2.167: icmp_seq=1 ttl=58 time=0.161 ms
64 bytes from 10.244.2.167: icmp_seq=2 ttl=58 time=0.084 ms
64 bytes from 10.244.2.167: icmp_seq=3 ttl=58 time=0.079 ms
```

**TTL 63 contre 58** : 5 sauts d'écart. Ce ne sont pas des chiffres décoratifs, c'est
la fabric qui se voit depuis l'intérieur du pod. La section 2 les nomme un par un.

---

## 2. Traceroute pod → pod : la capture de la phase 2

```
$ kubectl exec -n netlab netshoot-a-pbm7w -- traceroute -n -q1 10.244.2.167
traceroute to 10.244.2.167 (10.244.2.167), 30 hops max, 46 byte packets
 1  10.244.1.110   <- cilium_host du worker (passerelle du pod)
 2  10.1.1.1       <- leaf1
 3  10.0.0.4       <- spine2
 4  10.0.0.7       <- leaf2
 5  10.1.2.10      <- worker2
 6  *
 7  10.244.2.167   <- le pod de destination
```

Le trafic Kubernetes **traverse réellement la fabric**, saut par saut. C'est ce que le
native routing sans `autoDirectNodeRoutes` rend possible : avec cette option activée,
les nœuds se seraient parlé directement par le bridge Docker et ce traceroute aurait
montré un seul saut — il n'aurait rien démontré du tout.

Deux points à savoir expliquer :

- **Le saut 3 est spine2** alors qu'un run précédent passait par spine1. C'est l'ECMP :
  les deux chemins sont installés, le hash de flux choisit. Voir section 4.
- **Le saut 6 ne répond pas** (`*`). Le paquet traverse bien le datapath eBPF de Cilium
  sur worker2 avant d'entrer dans le pod, mais cet étage n'émet pas de
  `ICMP time-exceeded`. Absence de réponse ≠ absence de saut.

---

## 3. Les sessions eBGP

### Côté fabric — leaf1

```
$ docker exec clab-leaf-spine-leaf1 vtysh -c "show bgp summary"
BGP router identifier 10.255.0.11, local AS number 65011 VRF default vrf-id 0

Neighbor                        V         AS   MsgRcvd   MsgSent  ... State/PfxRcd   PfxSnt
spine1(10.0.0.0)                4      65001       110       111  ...            4        8
spine2(10.0.0.4)                4      65002       110       111  ...            4        8
l3bgp-cluster-worker(10.1.1.10) 4      65111       102       108  ...            1        8
```

### Côté fabric — leaf2

```
$ docker exec clab-leaf-spine-leaf2 vtysh -c "show bgp summary"
BGP router identifier 10.255.0.12, local AS number 65012 VRF default vrf-id 0

Neighbor                         V         AS   MsgRcvd   MsgSent  ... State/PfxRcd   PfxSnt
spine1(10.0.0.2)                 4      65001       361       362  ...            5        8
spine2(10.0.0.6)                 4      65002       361       362  ...            5        8
l3bgp-cluster-worker2(10.1.2.10) 4      65222       353       359  ...            1        8
```

Chaque leaf a **3 voisins** : ses deux spines (underlay phase 1) + son nœud kind
(phase 2). Le nœud n'annonce qu'**1 préfixe** — son podCIDR — et en reçoit 8.

### Côté cluster — le contrôleur BGP de Cilium

```
$ kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg bgp peers
Local AS   Peer AS   Peer Address   Session       Uptime   Family         Received   Advertised
65111      65011     10.1.1.1:179   established   16m58s   ipv4/unicast   8          1
```

```
$ cilium-dbg bgp routes advertised ipv4 unicast   # sur chaque agent
-- worker
VRouter   Peer       Prefix          NextHop     Attrs
65111     10.1.1.1   10.244.1.0/24   10.1.1.10   [{Origin: i} {AsPath: 65111} {Nexthop: 10.1.1.10}]
-- worker2
VRouter   Peer       Prefix          NextHop     Attrs
65222     10.1.2.1   10.244.2.0/24   10.1.2.10   [{Origin: i} {AsPath: 65222} {Nexthop: 10.1.2.10}]
-- control-plane
(aucune ligne — le nodeSelector des CiliumBGPClusterConfig ne le matche pas)
```

**Le next-hop est `10.1.1.10`, l'IP fabric — pas `172.18.0.x`, l'IP du bridge kind.**
C'est la preuve que `transport.sourceInterface: eth1` fait son travail : le next-hop
annoncé suit la source de la session TCP. Un seul réglage règle deux problèmes (session
acceptée par le leaf **et** next-hop routable dans la fabric).

Le control-plane qui n'annonce rien n'est pas un bug : c'est le `nodeSelector` sur le
label `fabric: leaf1|leaf2` qui l'exclut volontairement — il n'a pas de lien vers la
fabric.

---

## 4. ECMP jusqu'aux pods

```
$ docker exec clab-leaf-spine-leaf1 vtysh -c "show bgp ipv4 unicast 10.244.2.0/24"
BGP routing table entry for 10.244.2.0/24, version 8
Paths: (2 available, best #1, table default)
  65001 65012 65222
    10.0.0.0(spine1) from spine1(10.0.0.0) (10.255.0.1)
      Origin IGP, valid, external, multipath, bestpath-from-AS 65001, best (Router ID)
  65002 65012 65222
    10.0.0.4(spine2) from spine2(10.0.0.4) (10.255.0.2)
      Origin IGP, valid, external, multipath, bestpath-from-AS 65002
```

Et la traduction dans la RIB, donc dans le datapath :

```
$ docker exec clab-leaf-spine-leaf1 vtysh -c "show ip route 10.244.2.0/24"
Routing entry for 10.244.2.0/24
  Known via "bgp", distance 20, metric 0, best
  * 10.0.0.0, via eth1, weight 1
  * 10.0.0.4, via eth2, weight 1
```

Les deux chemins sont marqués `multipath` et **tous les deux installés** (`weight 1`
chacun). C'est `bgp bestpath as-path multipath-relax` qui l'autorise : les deux AS-path
ont la même longueur mais un contenu différent (`65001…` vs `65002…`), et sans ce
paramètre BGP refuserait de les considérer comme équivalents.

C'est le prolongement direct de l'ECMP validé en phase 1 sur les loopbacks — sauf qu'ici
la destination load-balancée est **un réseau de pods Kubernetes**.

---

## 5. Un ASN par nœud : la décision se lit dans l'AS-path

```
$ docker exec clab-leaf-spine-spine1 vtysh -c "show bgp ipv4 unicast"
     Network          Next Hop            Metric LocPrf Weight Path
 *>  10.1.1.0/24      10.0.0.1(leaf1)          0             0 65011 i
 *>  10.1.2.0/24      10.0.0.3(leaf2)          0             0 65012 i
 *>  10.244.1.0/24    10.0.0.1(leaf1)                        0 65011 65111 i
 *>  10.244.2.0/24    10.0.0.3(leaf2)                        0 65012 65222 i
 *>  10.255.0.1/32    0.0.0.0(spine1)          0         32768 i
 *>  10.255.0.2/32    10.0.0.1(leaf1)                        0 65011 65002 i
 *>  10.255.0.11/32   10.0.0.1(leaf1)          0             0 65011 i
 *>  10.255.0.12/32   10.0.0.3(leaf2)          0             0 65012 i
```

AS-path `65011 65111` pour le podCIDR de worker, `65012 65222` pour celui de worker2.
**Aucun worker ne voit son propre ASN dans l'AS-path de l'autre.**

Si les deux nœuds kind avaient partagé un ASN, la prévention de boucle eBGP aurait fait
rejeter le préfixe distant à l'arrivée : session Established, préfixe reçu, et pourtant
silencieusement jeté. La décision « un ASN par nœud » n'est donc pas cosmétique — c'est
elle qui rend le pod-to-pod possible. Convention retenue : `6500x` spines, `6501x` leaves,
`65NNN` nœuds kind (chiffre répété = index du nœud).

---

## 6. Le piège : Cilium annonce, il ne programme pas

```
$ docker exec l3bgp-cluster-worker ip route
default via 10.1.1.1 dev eth1
10.1.1.0/24 dev eth1 proto kernel scope link src 10.1.1.10
10.244.1.0/24 via 10.244.1.110 dev cilium_host proto kernel src 10.244.1.110
10.244.1.110 dev cilium_host proto kernel scope link
172.18.0.0/16 dev eth0 proto kernel scope link src 172.18.0.2
```

`Received 8` côté Cilium, et pourtant **aucune route `10.244.2.0/24` dans la table du
noyau**. Le BGP control plane de Cilium **annonce**, il ne programme pas les routes
reçues dans le datapath. Le trafic sort par la `default via 10.1.1.1` et c'est leaf1 qui
connaît le chemin (section 4).

Contre-intuitif, et une bonne question d'entretien : *« votre nœud reçoit 8 préfixes,
pourquoi n'en voit-on aucun dans `ip route` ? »*

---

## Deux symptômes à ne pas confondre

Session **Established mais 0 préfixe** a deux causes très différentes :

1. **RFC 8212** — un voisin eBGP sans politique n'annonce ni n'accepte rien. Neutralisé
   côté FRR par `no bgp ebgp-requires-policy`, présent depuis la phase 1.
2. **Un label selector qui ne matche rien** — `nodeSelector` du `CiliumBGPClusterConfig`,
   ou le selector qui relie le `CiliumBGPAdvertisement` au `CiliumBGPPeerConfig`.

Même symptôme, causes opposées. Vérifier aussi `ip addr` **avant** la config BGP : si
`eth1` a disparu (redémarrage des conteneurs kind), Cilium ne remonte **aucune erreur**,
retombe sur l'auto-détection, source la session en `172.18.0.x` — et le leaf la refuse.
La session reste bloquée en `Active`.
