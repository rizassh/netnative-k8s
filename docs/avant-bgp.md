## IP des Pods dans le namespace netlab, en fonction des worker

shazir@debian-lab:~/netnative-k8s$ kubectl get pods -n netlab -o wide
NAME               READY   STATUS    RESTARTS      AGE     IP             NODE                    NOMINATED NODE   READINESS GATES
netshoot-a-948fd   1/1     Running   1 (21m ago)   2d21h   10.244.2.230   l3bgp-cluster-worker2   <none>           <none>
netshoot-a-pbm7w   1/1     Running   1 (21m ago)   2d21h   10.244.1.65    l3bgp-cluster-worker    <none>           <none>
netshoot-b-gdmf7   1/1     Running   1 (21m ago)   2d21h   10.244.2.252   l3bgp-cluster-worker2   <none>           <none>
netshoot-b-rwnx6   1/1     Running   1 (21m ago)   2d21h   10.244.1.176   l3bgp-cluster-worker    <none>           <none>

## Test de ping intra-worker

shazir@debian-lab:~/netnative-k8s$ kubectl exec -n netlab netshoot-a-948fd -- ping 10.244.2.252
PING 10.244.2.252 (10.244.2.252) 56(84) bytes of data.
64 bytes from 10.244.2.252: icmp_seq=1 ttl=63 time=0.102 ms
64 bytes from 10.244.2.252: icmp_seq=2 ttl=63 time=0.037 ms
64 bytes from 10.244.2.252: icmp_seq=3 ttl=63 time=0.032 ms
64 bytes from 10.244.2.252: icmp_seq=4 ttl=63 time=0.036 ms

## Test de ping inter-worker

shazir@debian-lab:~/netnative-k8s$ kubectl exec -n netlab netshoot-a-948fd -- ping 10.244.1.65
PING 10.244.1.65 (10.244.1.65) 56(84) bytes of data.

Échec du ping, volontaire et attendu car il n'y a pas de routes vers l'autre subnet. 

## Table de routage sur worker

shazir@debian-lab:~/netnative-k8s$ docker exec -it l3bgp-cluster-worker ip route
default via 10.1.1.1 dev eth1
10.1.1.0/24 dev eth1 proto kernel scope link src 10.1.1.10
10.244.1.0/24 via 10.244.1.110 dev cilium_host proto kernel src 10.244.1.110
10.244.1.110 dev cilium_host proto kernel scope link
172.18.0.0/16 dev eth0 proto kernel scope link src 172.18.0.2

Absence de la route vers 10.244.2.0/24, d'où l'échec du ping inter-worker.
