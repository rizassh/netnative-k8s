## Test de ping intra-worker

shazir@debian-lab:~/netnative-k8s$ kubectl exec -n netlab netshoot-a-948fd -- ping 10.244.2.252
PING 10.244.2.252 (10.244.2.252) 56(84) bytes of data.
64 bytes from 10.244.2.252: icmp_seq=1 ttl=63 time=0.043 ms
64 bytes from 10.244.2.252: icmp_seq=2 ttl=63 time=0.030 ms
64 bytes from 10.244.2.252: icmp_seq=3 ttl=63 time=0.032 ms

## Test de ping inter-worker

shazir@debian-lab:~/netnative-k8s$ kubectl exec -n netlab netshoot-a-948fd -- ping 10.244.1.65
PING 10.244.1.65 (10.244.1.65) 56(84) bytes of data.
64 bytes from 10.244.1.65: icmp_seq=1 ttl=58 time=0.130 ms
64 bytes from 10.244.1.65: icmp_seq=2 ttl=58 time=0.086 ms
64 bytes from 10.244.1.65: icmp_seq=3 ttl=58 time=0.095 ms
64 bytes from 10.244.1.65: icmp_seq=4 ttl=58 time=0.083 ms


## Table de routage sur worker

shazir@debian-lab:~/netnative-k8s$  docker exec -it l3bgp-cluster-worker ip route
default via 10.1.1.1 dev eth1
10.1.1.0/24 dev eth1 proto kernel scope link src 10.1.1.10
10.244.1.0/24 via 10.244.1.110 dev cilium_host proto kernel src 10.244.1.110
10.244.1.110 dev cilium_host proto kernel scope link
172.18.0.0/16 dev eth0 proto kernel scope link src 172.18.0.2

implicite : 10.244.2.230 via 10.1.1.1 dev eth1 src 10.1.1.10
Received 7 côté Cilium, mais aucune route 10.244.2.0/24 dans le noyau : le BGP control plane annonce, il ne programme pas les routes reçues. Le trafic sort par la default via 10.1.1.1, et c'est leaf1 qui sait où aller. À savoir expliquer — c'est contre-intuitif et ça fait une bonne question d'entretien.
