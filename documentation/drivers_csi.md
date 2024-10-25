# Drivers CSI

## Présentation

CSI= Container Storage Interface

Les CSI sont les éléments principaux du storage sous OKD. Il n\'y a pas
si longtemps, les drivers de storage étaient inclus directement dans le
code OKD, puis dans un soucis de simplification et d\'entretien du code,
les développeurs ont laissé les fournisseurs d\'espace disque écrire
leur propre code pour faire intéragir leurs solutions de stockage avec
Kubernetes. Les driver CSI sont donc un standard qui sert d\'interface
indépendamment de la nature du stockage. Ces fournisseurs peuvent être
de différentes nature:

-   cloud
-   on premise
-   distribués
-   block
-   filesystem

Une liste non exhaustive de ces drivers peut être trouvée ici:
<https://kubernetes-csi.github.io/docs/drivers.html>

Chaque driver présente des caractéristiques d\'accès aux données
différentes: RWO/RWX, snapshots, expansion, stockage éphémère, etc\...

Dans notre cas de figure, nous avons installé OKD avec le provider
`ovirt` fourni avec l\'installateur `IPI`. Notre driver par défaut est
donc `csi.ovirt.org`.

On retrouve toute les parties nécessaires au fonctionnement de ce driver
dans le namespace `openshift-cluster-csi-drivers`

``` /bash
oc get all -n openshift-cluster-csi-drivers
NAME                                               READY   STATUS    RESTARTS          AGE
pod/ovirt-csi-driver-controller-7548ffcb77-8wgnd   7/7     Running   506 (4d1h ago)    336d
pod/ovirt-csi-driver-controller-7548ffcb77-jdnnb   7/7     Running   574 (28h ago)     375d
pod/ovirt-csi-driver-node-4chgv                    3/3     Running   536 (4d1h ago)    376d
pod/ovirt-csi-driver-node-7bvnv                    3/3     Running   1724 (4d1h ago)   368d
pod/ovirt-csi-driver-node-g89k6                    3/3     Running   1672 (4d1h ago)   439d
pod/ovirt-csi-driver-node-jj98q                    3/3     Running   536 (4d1h ago)    439d
pod/ovirt-csi-driver-node-jthsw                    3/3     Running   1658 (4d1h ago)   368d
pod/ovirt-csi-driver-node-tp7gq                    3/3     Running   1762 (4d1h ago)   439d
pod/ovirt-csi-driver-node-xrgfd                    3/3     Running   1781 (3d ago)     439d
pod/ovirt-csi-driver-node-xz7qs                    3/3     Running   1638 (4d1h ago)   368d
pod/ovirt-csi-driver-node-zglsb                    3/3     Running   1763 (4d1h ago)   439d
pod/ovirt-csi-driver-node-zl2r9                    3/3     Running   1763 (4d1h ago)   439d
pod/ovirt-csi-driver-operator-757955c497-h9fhk     1/1     Running   56                375d

NAME                                          TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)           AGE
service/ovirt-csi-driver-controller-metrics   ClusterIP   172.30.145.96   <none>        443/TCP,444/TCP   439d

NAME                                   DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
daemonset.apps/ovirt-csi-driver-node   10        10        10      10           10          <none>          439d

NAME                                          READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/ovirt-csi-driver-controller   2/2     2            2           439d
deployment.apps/ovirt-csi-driver-operator     1/1     1            1           439d

NAME                                                     DESIRED   CURRENT   READY   AGE
replicaset.apps/ovirt-csi-driver-controller-5479cb9f94   0         0         0       361d
replicaset.apps/ovirt-csi-driver-controller-674f5b5d67   0         0         0       439d
replicaset.apps/ovirt-csi-driver-controller-7548ffcb77   2         2         2       439d
replicaset.apps/ovirt-csi-driver-operator-556577958d     0         0         0       361d
replicaset.apps/ovirt-csi-driver-operator-757955c497     1         1         1       439d
```

De plus, on retrouve les paramètres d\'accès à l\'api d\'ovirt sous
forme de secret déclaré dans le deployment `ovirt-csi-driver-controller`

``` /bash
oc describe secrets -n openshift-cluster-csi-drivers ovirt-credentials
```

Pour utiliser ce driver, Kubernetes a besoin de la défintion d\'une
`storageClass`

``` /bash
NAME                                  PROVISIONER                             RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
nfs-csi                               nfs.csi.k8s.io                          Delete          Immediate           false                  146m
nfs-csi3                              nfs.csi.k8s.io                          Delete          Immediate           false                  58m
ocs-storagecluster-ceph-rbd           openshift-storage.rbd.csi.ceph.com      Delete          Immediate           true                   368d
ocs-storagecluster-ceph-rgw           openshift-storage.ceph.rook.io/bucket   Delete          Immediate           false                  368d
ocs-storagecluster-cephfs (default)   openshift-storage.cephfs.csi.ceph.com   Delete          Immediate           true                   368d
openshift-storage.noobaa.io           openshift-storage.noobaa.io/obc         Delete          Immediate           false                  368d
ovirt-csi-sc                          csi.ovirt.org                           Delete          Immediate           true                   33d
ovirt-csi2-sc                         csi.ovirt.org                           Delete          Immediate           true                   67d
```

`ovirt-csi-sc` est la storageClass par défaut. Pour en définir une
autre, il faut rajouter l\'annotation
**storageclass.kubernetes.io/is-default-class: \"true\"** à la classe
choisie.

``` /yaml
metadata:
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
```

Dès lors, lors de la création d\'un pvc, on pourra choisir la storage
class de son choix:

``` /yaml
spec:
  accessModes:
  - ReadWriteMany
  resources:
    requests:
      storage: 1Gi
  storageClassName: ocs-storagecluster-cephfs
```

### Limites du driver csi.ovirt.org

Le driver fonctionne très bien pour les activités courantes, notamment
en ce qui concerne les pvc \"persistent volume claim\"

Il peut manquer certaines fonctions:

-   RWX: l\'accès multiple à un pvc par différents pods/containers.
    Cependant cette fonction est difficilement utilisable puisqu\'elle
    met en concurrence en écriture plusieurs pods, pouvant conduire à
    des défauts d\'écriture. Cette fonctionnalité est donc à bannir de
    services tels que les bases de données.
-   les snapshots qui sont utilisés pour les sauvegardes velero

## Openshift Data Foundation

Redhat propose de faciliter l\'accès au stockage de données en déployant
une couche d\'abstraction à base de Ceph qui permet de combler les
limitations des drivers CSI classiques tels que `csi.ovirt.org`.
L\'installation se fait à partir de l\'opérateur du même nom dans
`Operator Hub`.

**Personnalisation:**

<https://access.redhat.com/documentation/en-us/red_hat_openshift_data_foundation/4.15/html-single/managing_and_allocating_storage_resources/index#how-to-use-dedicated-worker-nodes-for-openshift-data-foundation_rhodf>

-   `infra` node-role label

``` /bash
oc label node <node> node-role.kubernetes.io/infra=""
oc label node <node> cluster.ocs.openshift.io/openshift-storage=""
```

-   `tainted`

``` /bash
oc adm taint node <node> node.ocs.openshift.io/storage="true":NoSchedule
```

-   Result

``` /bash
oc get nodes 
NAME                          STATUS   ROLES                  AGE    VERSION
orchidee-ccbm8-master-0       Ready    control-plane,master   446d   v1.25.7+eab9cc9
orchidee-ccbm8-master-1       Ready    control-plane,master   446d   v1.25.7+eab9cc9
orchidee-ccbm8-master-2       Ready    control-plane,master   446d   v1.25.7+eab9cc9
orchidee-ccbm8-master-30      Ready    control-plane,master   383d   v1.25.7+eab9cc9
orchidee-ccbm8-worker-9pg8j   Ready    worker                 446d   v1.25.7+eab9cc9
orchidee-ccbm8-worker-cb2lg   Ready    infra,worker           375d   v1.25.7+eab9cc9
orchidee-ccbm8-worker-hqwhs   Ready    infra,worker           375d   v1.25.7+eab9cc9
orchidee-ccbm8-worker-hxmn4   Ready    infra,worker           375d   v1.25.7+eab9cc9
orchidee-ccbm8-worker-v55b4   Ready    worker                 446d   v1.25.7+eab9cc9
orchidee-ccbm8-worker-zhgql   Ready    worker                 446d   v1.25.7+eab9cc9

oc get node -l cluster.ocs.openshift.io/openshift-storage=
NAME                          STATUS   ROLES          AGE    VERSION
orchidee-ccbm8-worker-cb2lg   Ready    infra,worker   375d   v1.25.7+eab9cc9
orchidee-ccbm8-worker-hqwhs   Ready    infra,worker   375d   v1.25.7+eab9cc9
orchidee-ccbm8-worker-hxmn4   Ready    infra,worker   375d   v1.25.7+eab9cc9
```

<https://www.ibm.com/docs/fr/storage-fusion/2.4?topic=services-openshift-data-foundation>

``` /bash
oc describe storagecluster -n openshift-storage ocs-storagecluster
---
  Storage Device Sets:
    Config:
    Count:  1
    Data PVC Template:
      Metadata:
      Spec:
        Access Modes:
          ReadWriteOnce
        Resources:
          Requests:
            Storage:         512Gi
        Storage Class Name:  ovirt-csi-sc
        Volume Mode:         Block
      Status:
    Name:  ocs-deviceset-ovirt-csi-sc
    Placement:
    Portable:  true
    Prepare Placement:
    Replica:  3
    Resources:
---
```

Toutes les commandes suivantes affirment que le `clusterStorage` ODF est
composé de 3 pods **rook-ceph-osd** qui résident sur les 3 noeuds
`infra` et qui distribuent chacun un stockage distribué de 512GB

``` /bash
oc describe cephcluster -n openshift-storage
oc -n openshift-storage get pvc
NAME                                       STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS                  AGE
db-noobaa-db-pg-0                          Bound    pvc-fb2177aa-acb9-4c22-bead-1b381a44d2b6   50Gi       RWO            ocs-storagecluster-ceph-rbd   375d
ocs-deviceset-ovirt-csi-sc-0-data-0c5vkf   Bound    pvc-9d92b4a5-02d8-454e-abc2-db33e0cb6561   512Gi      RWO            ovirt-csi-sc                  375d
ocs-deviceset-ovirt-csi-sc-1-data-06r66g   Bound    pvc-f48003e0-c8cc-4ea0-8e32-66ad74696681   512Gi      RWO            ovirt-csi-sc                  375d
ocs-deviceset-ovirt-csi-sc-2-data-0xfnsv   Bound    pvc-16e0f284-3aea-400c-a348-3786a43838c0   512Gi      RWO            ovirt-csi-sc                  375d
rook-ceph-mon-a                            Bound    pvc-2e4e7fe8-a50c-493e-b114-bc4f3e955727   50Gi       RWO            ovirt-csi-sc                  375d
rook-ceph-mon-b                            Bound    pvc-31520f0b-7e84-4c31-9af4-de3207471f65   50Gi       RWO            ovirt-csi-sc                  375d
rook-ceph-mon-c                            Bound    pvc-b0e2dcb0-dd4b-4ec5-92f8-58afb82ff00e   50Gi       RWO            ovirt-csi-sc                  375d

oc describe pvc ocs-deviceset-ovirt-csi-sc-0-data-0c5vkf -n openshift-storage
---
Capacity:      512Gi
Access Modes:  RWO
VolumeMode:    Block
Used By:       rook-ceph-osd-1-78d5dffbd6-f7vv7
               rook-ceph-osd-prepare-eceee02de04785a62dca72ad574a0dc6-wx4xs
---
```

L\'opérateur installe 2 nouveaux drivers csi:

``` /bash
oc get csidrivers.storage.k8s.io 
NAME                                    ATTACHREQUIRED   PODINFOONMOUNT   STORAGECAPACITY   TOKENREQUESTS   REQUIRESREPUBLISH   MODES                  AGE
csi.ovirt.org                           true             false            false             <unset>         false               Persistent             439d
openshift-storage.cephfs.csi.ceph.com   true             false            false             <unset>         false               Persistent             368d
openshift-storage.rbd.csi.ceph.com      true             false            false             <unset>         false               Persistent             368d
```

avec deux nouvelles classes associées:

``` /bash
oc get sc
NAME                                  PROVISIONER                             RECLAIMPOLICY   VOLUMEBINDINGMODE   ALLOWVOLUMEEXPANSION   AGE
ocs-storagecluster-ceph-rbd           openshift-storage.rbd.csi.ceph.com      Delete          Immediate           true                   368d
ocs-storagecluster-ceph-rgw           openshift-storage.ceph.rook.io/bucket   Delete          Immediate           false                  368d
ocs-storagecluster-cephfs (default)   openshift-storage.cephfs.csi.ceph.com   Delete          Immediate           true                   368d
openshift-storage.noobaa.io           openshift-storage.noobaa.io/obc         Delete          Immediate           false                  368d
ovirt-csi-sc                          csi.ovirt.org                           Delete          Immediate           true                   33d
```

A noter qu\'en plus de **ocs-storagecluster-ceph-rbd** et de
**ocs-storagecluster-cephfs**, deux autres storageClass sont installées
mais elles ne concernent uniquement que le stockage objet (bucket).

### Résumé

ODF nous offre la possibilité de contourner les limites des drivers CSI
traditionnels en installant un serveur intégré `rook.io` et `nooba.io`
compatible `Ceph` qui propose 3 modes d\'utilisation:

-   file (Cephfs) =\> ocs-storagecluster-cephfs (csi) sur base de CephFS
    (Rook)
-   block (RADOS) =\> ocs-storagecluster-ceph-rbd (csi) sur base de Ceph
    (Rook)
-   object (RGW) backs the persistent volume, gestion pv, pvc =\>
    ocs-storagecluster-ceph-rgw (Nooba)

Usage:

-   Block storage for databases
-   Shared file storage for continuous integration, messaging, and data
    aggregation
-   Object storage for archival, backup, and media storage

## Drivers CSI Dell

Dell fournit des drivers CSI pour utiliser ses baies de disques depuis
k8s. Il y a plusieurs générations de drivers CSI, et jusqu\'à la version
1.6, l\'opérator dans okd permettait de gérer les différents types de
baies directement depuis l\'interface ainsi que d\'installer
automatiquement des storageClass associées.

Depuis la version 1.7, il faut passer comme étape préalable par
l\'installation de l\'opérateur `ContainerStorageModule` CSM.

Puis suivre les étapes suivantes:
<https://dell.github.io/csm-docs/docs/deployment/csmoperator/drivers/unity/>

Créer un namespace

``` /bash
kubectl create namespace unity
```

Ajouter l\'authentification Dockerhub:

``` /bash
oc create secret docker-registry docker.io --docker-server=docker.io --docker-username= --docker-password=
oc secrets link unity-controller docker.io --for=pull
oc secrets link unity-node docker.io --for=pull
```

Créer un fichier secret.yaml

``` /bash
   storageArrayList:
   - arrayId: "CKM00164400884"                 # unique array id of the Unisphere array
     username: "admin"                        # username for connecting to API
     password: "password"                    # password for connecting to API
     endpoint: "https://sanpedro.v106.abes.fr/"           # full URL path to the Unity XT API
     skipCertificateValidation: true         # indicates if client side validation of (management)server's certificate can be skipped
     isDefault: true                         # treat current array as a default (would be used by storage classes without arrayID parameter)
```

Créer le secret à partir de secret.yaml

``` /bash
kubectl create secret generic unity-creds -n unity --from-file=config=secret.yaml
kubectl create secret generic unity-creds -n unity --from-file=config=secret.yaml -o yaml --dry-run | kubectl replace -f -
```

Choisir sa version driver à partir de la page
<https://github.com/dell/csm-operator/tree/main/samples>

``` /bash
curl https://raw.githubusercontent.com/dell/csm-operator/main/samples/storage_csm_unity_v2100.yaml | kubectl create -f -
```

On vérifie que le déploiement du driver:

``` /bash
kubectl get all -n unity
kubectl get csm -n unity
```

Vérification de la présence du driver **csi-unity.dellemc.com**

``` /bash
oc get csidrivers.storage.k8s.io 
NAME                                    ATTACHREQUIRED   PODINFOONMOUNT   STORAGECAPACITY   TOKENREQUESTS   REQUIRESREPUBLISH   MODES                  AGE
csi-unity.dellemc.com                   true             true             true              <unset>         false               Persistent,Ephemeral   6d19h
```

Il reste à installer les storageClass à partir de
<https://github.com/dell/csi-unity/tree/main/samples> exemple pour le
fc:

``` /bash
curl https://raw.githubusercontent.com/dell/csi-unity/main/samples/storageclass/unity-fc.yaml | kubectl apply -f -
```

### Remarque

Les drivers Dell permettent au cluster k8s d\'intéragir avec les baies
de diques (cher nous unity et powerstore) à partir de protocoles tout à
fait traditionnels tels que FC ou iSCSI. De ce fait, notre installation
virtuelle ne pourra utiliser ce driver puisqu\'elle nécessite que les
noeuds possèdent physiquement un accès de bas niveau aux contrôleurs
HBA. Ce driver Dell est donc l\'illustration que le choix du driver CSI
se fait en fonction du type d\'installation choisi. Ce qui nous fait
rebondir sur une installation mixte virtuelle/physique décrite dans ce
document:
<https://infohub.delltechnologies.com/en-us/p/hybrid-kubernetes-clusters-with-powerstore-csi/>

## Drivers CSI NFS

### Installation

Ce driver a pour avantage d\'être universel et de proposer un accès
multiple

<https://github.com/kubernetes-csi/csi-driver-nfs/blob/master/docs/install-csi-driver-v4.7.0.md>

``` /bash
curl -skSL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/v4.7.0/deploy/install-driver.sh | bash -s v4.7.0 --
```

On vérifie:

``` /bash
kubectl -n kube-system get pod -o wide -l app=csi-nfs-controller
kubectl -n kube-system get pod -o wide -l app=csi-nfs-node
```

On crée une storage Class:

``` /bash
curl https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/master/deploy/v4.7.0/storageclass.yaml | kubectl apply -f -
```

ou

``` /bash
cat <<EOF | oc apply -f -
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
provisioner: nfs.csi.k8s.io
parameters:
  server: nfs-server.default.svc.cluster.local
  share: /
  # csi.storage.k8s.io/provisioner-secret is only needed for providing mountOptions in DeleteVolume
  # csi.storage.k8s.io/provisioner-secret-name: "mount-options"
  # csi.storage.k8s.io/provisioner-secret-namespace: "default"
reclaimPolicy: Delete
volumeBindingMode: Immediate
mountOptions:
  - nfsvers=4.1
EOF
```

Vérification de la présence du driver **nfs.csi.k8s.io**

``` /bash
oc get csidrivers.storage.k8s.io 
NAME                                    ATTACHREQUIRED   PODINFOONMOUNT   STORAGECAPACITY   TOKENREQUESTS   REQUIRESREPUBLISH   MODES                  AGE
nfs.csi.k8s.io                          false            false            false             <unset>         false               Persistent             6d1h
```

### Exemple d\'utilisation

Contrairement à un type de driver CSI en mode block comme **ovirt-csi**,
le driver NFS de mode filesystem prend en compte la notion de droits de
fichier. La plupart du temps, définir un partage de fichiers NFS en
`root_squash` suffit à donner assez de droits pour que le client NFS
puisse agir avec des droits root.

-   Partage sur methana:

``` /bash
cat /etc/exports
/pool_SAS_2/OKD *(rw,root_squash)
```

-   Création de la StorageClass

``` /bash
oc apply -f - <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
mountOptions:
- nfsvers=4.1
parameters:
  server: methana.v102.abes.fr
  share: /pool_SAS_2/OKD
provisioner: nfs.csi.k8s.io
reclaimPolicy: Delete
volumeBindingMode: Immediate
EOF
```

-   Création du pvc

``` /bash
oc apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  labels:
    io.kompose.service: movies-wikibase-mysql-claim6
  name: movies-wikibase-mysql-claim6
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 2Gi
  storageClassName: nfs-csi
EOF
```

-   Utilisation du pvc précédemment créé dans un deployment:

``` /bash
oc set volume deploy/movies-wikibase-mysql --add --name=movies-wikibase-mysql-claim6  --claim-name=movies-wikibase-mysql-claim6 --mount-path /var/lib/mysql/
```

Si on regarde sur le partage de methana, on observe bien la création
d\'un répertoire:

``` /bash
[root@methana pool_SAS_2]# ll OKD
total 4
drwxr-xr-x. 6 nobody nobody 4096 May  7 17:24 pvc-48d777ae-dde9-4c27-85c6-4390a13b26fe
```

**précision** Comme nous n\'avons pas précisé d\'utilisateur comme
option de partage, c\'est l\'utilisateur `nobody` avec l\'uid `65534`
qui devra être utilisé par le client pour avoir les droits root. Si on
ne précise pas cela, le container restera en mode `pending` du fait que
l\'entrypoint de l\'image mysql ne peut pas changer les droits du
répertoire `/var/lib/mysql`

-   On rajoute donc l\'uid `65534` comme ayant utilisateur qui déploie
    l\'image:

``` /bash
oc get -o json deployment movies-wikibase-mysql | jq '.spec.template.spec.containers[]+={securityContext:{allowPrivilegeEscalation: true, runAsUser: 65534}}' | oc apply -f -
# ou bien
oc patch deployment movies-wikibase-mysql -p '{"spec":{"template":{"spec":{"containers:[{"securityContext":{"allowPrivilegeEscalation": "true", "runAsUser": "65534"}}]}}}}'
```

### Snapshot CSI

[Snapshots CSI](snapshot_csi.md)
