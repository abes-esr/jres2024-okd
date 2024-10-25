# Gestion des noeuds OKD

## Généralités

<https://docs.okd.io/3.11/admin_guide/manage_nodes.html>

Par défaut, l\'installateur OKD provisionnent 6 VMS

``` /bash
[root@vm1-dev ~]# oc get nodes -o wide
NAME                        STATUS   ROLES    AGE   VERSION                INTERNAL-IP     EXTERNAL-IP   OS-IMAGE                        KERNEL-VERSION            CONTAINER-RUNTIME
v212-t4k2k-master-0         Ready    master   19d   v1.20.0+5fbfd19-1046   10.34.212.60    <none>        Fedora CoreOS 33.20210217.3.0   5.10.12-200.fc33.x86_64   cri-o://1.20.0
v212-t4k2k-master-1         Ready    master   19d   v1.20.0+5fbfd19-1046   10.34.214.242   <none>        Fedora CoreOS 33.20210217.3.0   5.10.12-200.fc33.x86_64   cri-o://1.20.0
v212-t4k2k-master-2         Ready    master   19d   v1.20.0+5fbfd19-1046   10.34.214.243   <none>        Fedora CoreOS 33.20210217.3.0   5.10.12-200.fc33.x86_64   cri-o://1.20.0
v212-t4k2k-worker-0-dgjzp   Ready    worker   18d   v1.20.0+5fbfd19-1046   10.34.214.245   <none>        Fedora CoreOS 33.20210217.3.0   5.10.12-200.fc33.x86_64   cri-o://1.20.0
v212-t4k2k-worker-0-wsmn4   Ready    worker   19d   v1.20.0+5fbfd19-1046   10.34.214.244   <none>        Fedora CoreOS 33.20210217.3.0   5.10.12-200.fc33.x86_64   cri-o://1.20.0
v212-t4k2k-worker-0-z6pdg   Ready    worker   19d   v1.20.0+5fbfd19-1046   10.34.212.66    <none>        Fedora CoreOS 33.20210217.3.0   5.10.12-200.fc33.x86_64   cri-o://1.20.0
```

Les masters correspondent à la partie controlplane et les workers au
dataplane. Les workers sont donc les noeuds qui font tourner les
containers.

    oc describe node v212-t4k2k-worker-0-dgjzp
    oc adm top nodes

## Scaling

<https://docs.openshift.com/container-platform/4.6/machine_management/manually-scaling-machineset.html>

Il est très facile de modifier le nombre de workers

Les machinesets sont les groupes de workers par cloud. Dans notre cas,
nous n\'avons qu\'un seul provider `ovirt`

    oc get machinesets -n openshift-machine-api

On modifie le nombre de `replica` aussi simplement que

    oc scale --replicas=2 machineset <machineset> -n openshift-machine-api

Une nouvelle VM est immédiatement crée sous ovirt, s\'auto-provisionnant
par ignition, avec la création des containers de services. La VM peut
mettre une dizaine de minutes avant d\'être disponible dans le cluster
OKD.

Ou bien en éditant le fichier correspondant

    oc edit machineset <machineset> -n openshift-machine-api

Dans le cas où on veut diminuer le nombre de worker, on a la possibilité
de choisir quel worker retirer : `Random`, `Newest` ou `Oldest` en
éditant le fichier précédent avec ces paramètres:

    spec:
      deletePolicy: <delete_policy>
      replicas: <desired_replica_count>
