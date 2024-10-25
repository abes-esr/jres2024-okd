# Scaling des noeuds

OKD fonctionne avec 6 noeuds `coreos` au minimum:

-   3 masters ou etcd pour le contrôle plane
-   3 workers pour les conteneurs applicatifs

``` /bash
NAME                          STATUS   ROLES                  AGE   VERSION
orchidee-hw8b4-master-0       Ready    control-plane,master   57d   v1.25.4+a34b9e9
orchidee-hw8b4-master-1       Ready    control-plane,master   57d   v1.25.4+a34b9e9
orchidee-hw8b4-master-2       Ready    control-plane,master   57d   v1.25.4+a34b9e9
orchidee-hw8b4-worker-mwr49   Ready    worker                 57d   v1.25.4+a34b9e9
orchidee-hw8b4-worker-nvcjf   Ready    worker                 57d   v1.25.4+a34b9e9
orchidee-hw8b4-worker-png59   Ready    worker                 57d   v1.25.4+a34b9e9
```

Sous le provider `oVirt`, ils sont tous issus du template
`orchidee-hw8b4-rhcos` créé à l\'installation d\'OKD. Ils ont tous par
défaut ces caractéristiques:

-   16 GiB de RAM
-   120 GiB d\'espace disque
-   4 vCPUs

## Cas d\'un noeud worker

<https://docs.openshift.com/container-platform/4.12/machine_management/manually-scaling-machineset.html>

C\'est le cas plus simple car la fonctionnalité est prévue nativement
dans OKD.

-   Récupérer le machineset

``` /bash
oc get machinesets -n openshift-machine-api
```

-   Récupérer les noeuds du machineset

``` /bash
oc get machine -n openshift-machine-api
```

-   S\'il faut réduire le nombre de replicas, choisir le worker à
    supprimer :

``` /bash
oc annotate machine/orchidee-hw8b4-worker-mwr49 -n openshift-machine-api machine.openshift.io/delete-machine="true"
```

-   Ajuster le nombre de replicas à la hausse ou à la baisse

``` /bash
oc scale --replicas=2 machineset orchidee-hw8b4-worker -n openshift-machine-api
```

## Cas d\'un noeud master

<https://docs.okd.io/latest/backup_and_restore/control_plane_backup_and_restore/replacing-unhealthy-etcd-member.html#restore-replace-stopped-etcd-member_replacing-unhealthy-etcd-member>

Le daemon `etcd` permet de distribuer les charges sur les noeuds du
cluster. C\'est la particularité qui rend la scalabilité du control
plane plus délicate à effectuer.

-   Il faut récupérer la configuration d\'un noeud master existant et
    l\'adapter en le renommant, puis le déployer dans le cluster.

``` /bash
oc get machine orchidee-7cn9g-master-0 -n openshift-machine-api -o json | jq 'del (.status)'
                                                                        | jq 'del(.spec.providerID)'
                                                                        | jq '.metadata.name = "orchidee-7cn9g-master-10"'
                                                                        | yq eval -P > new_master.yaml
oc apply -f new_master.yaml
```

ou bien en une commande (`oc` accepte également le format json en
entrée)

``` /bash
oc get machine orchidee-7cn9g-master-0 -n openshift-machine-api -o json | jq 'del (.status)'
                                                                        | jq 'del(.spec.providerID)'
                                                                        | jq '.metadata.name = "orchidee-7cn9g-master-10"'
                                                                        | oc apply -f -
```

Cela a pour effet de déployer une nouvelle vm sous `oVirt` à partir du
template `coreos`.

Il existe cependant un bug dans le déploiement de cette vm qui
l\'empêche d\'être provisionée avec le nombre de core minimum (4) qui
permet de lancer les `cluster operator` `etcd` et `kube-apiserver` Il se
peut donc que le déploiement échoue avec ce type d\'erreur de resources:

``` /bash
Warning  UnexpectedAdmissionError  104m  kubelet, crawford-libvirt-xqscg-master-0  Unexpected error while attempting to recover from admission failure: preemption: \ 
error finding a set of pods to preempt: no set of running pods found to reclaim resources: [(res: memory, q: 11067392), ]
```

Il faut donc arrêter le master fraîchement créé dans ovirt pour ajouter
le nombre de coeur à 4 vcpus.

``` /bash
oc debug node/orchidee-7cn9g-master-20 -- chroot /host shutdown now
```

Puis on redémarre le master dans ovirt.

-   Une fois le noeud up, s\'assurer que la vérification du quorum est
    bien activée

``` /bash
oc patch etcd/cluster --type=merge -p '{"spec": {"unsupportedConfigOverrides": null}}'
```

-   Vérifier que le nouveau noeud a bien été intégré en tant que membre
    du cluster

``` /bash
oc -n openshift-etcd get pods -l k8s-app=etcd
oc rsh -n openshift-etcd etcd-orchidee-ccbm8-master-30
etcdctl member list -w table
```
