# Backups OKD

Le backup au sens `kubernetes` se fait sous forme de manifests. Il faut
alors distinguer deux formes de backup:

1.  Le backup du cluster etcd qui va permettre de frestaurer la
    configuration des noeuds master `control plane`
2.  le backup des applications hébergées sous le cluster etcd comprenant
    deux sous-éléments:
    1.  les manifests
    2.  les volumes persistants

## Backup cluster etcd

<https://docs.okd.io/latest/backup_and_restore/control_plane_backup_and_restore/backing-up-etcd.html#backing-up-etcd-data_backup-etcd>

### Prérequis

-   L\'ensemble des **cluster operators** doit être en parfait
    fonctionnement

``` /bash
oc get co
```

Si ce n\'est pas le cas, rétablir les cluster operators défaillants
suivant
<https://wiki.abes.fr/doku.php?id=okd:reparation_d_un_noeud_etcd>

-   il faut impérativement faire la sauvegarde 24h après l\'installation
    du cluster
-   l\'opération peut être indifférement accomplie sur n\'importe quel
    noeud `etcd`

### Procédure

``` /bash
oc get nodes
oc debug node/orchidee-7cn9g-master
chroot /host
/usr/local/bin/cluster-backup.sh /home/core/assets/backup
```

Cela produit les artefacts suivants

``` /bash
sh-5.2# ls -hl /home/core/assets/backup/
total 114M
-rw-------. 1 root root 114M May  3 16:43 snapshot_2023-05-03_164340.db
-rw-------. 1 root root  78K May  3 16:43 static_kuberesources_2023-05-03_164340.tar.gz
```

ou bien en une commande:

``` /bash
oc get nodes
oc debug node/orchidee-ccbm8-master-30 -- chroot /host /usr/local/bin/cluster-backup.sh /home/core/assets/backup
```

Il reste alors à sauvegarder les artifacts:

``` /bash
rsync -av core@orchidee-7cn9g-master-1.v102.abes.fr:/home/core/assets/backup backup-v102 --rsync-path="sudo rsync"
```

## Backup d\'une application

### Grandes étapes

<https://docs.okd.io/4.8/backup_and_restore/application_backup_and_restore/installing/installing-oadp-mcg.html>

1.  Prérequis
    1.  Installation de l\'opérateur Data Foundation (namespace
        **openshift-storage**)
    2.  Installation de l\'opérateur OADP (namespace **openshift-adp**)
    3.  Installation des différents CLI
2.  Configuration au niveau d\'OKD
    1.  Création du **backing store**
    2.  Création de la **BucketClass**
    3.  Création de l\'**Object Bucket Claim**
    4.  Récupération des informations S3 précédemment crées
    5.  Création du **secret** contenantles identifiants S3
    6.  Création du fichier **DataProtectionApplication**

### Pré-requis

#### Installation des opérateurs ODF (OpenShift Data Foundation) et OADP (OpenShift Data Protection API)

Depuis l\'UI: Click OperatorHub → Search OADP and ODF. Si les opérateurs
ne sont pas trouvés, étendre la recherche à tous les namespaces.

#### Récupération du certificat root du routeur openshift

Il servira à l\'ensemble des commandes CLI des différents logiciels

``` /bash
oc extract secret/router-certs-default -n openshift-ingress --to=/tmp --keys=tls.crt
# Pour uniquement l'afficher
oc extract secret/router-certs-default -n openshift-ingress --to=- --keys=tls.crt
# ou bien
oc get secret -n openshift-ingress router-certs-default -o go-template='{{index .data "tls.crt" }}' | base64 --decode
```

#### Installation du client Velero

Velero est le logiciel de sauvegarde exclusivement en mode objet intégré
à OKD. Un serveur S3 compatible doit donc être présent avant tout
backup. Il se décompose en 2 parties:

1.  La sauvegarde de configuration (sous forme de manifests): partie
    `BackupLocation`
2.  La sauvegardes des volumes persistents soit:
    1.  par snapshot CSI si le provider le supporte (Ceph CSI le
        supporte mais ce n\'est pas le cas d\'oVirt CSI): partie
        `SnapshotLocation`
    2.  par le logiciel de snapshot filesystem `Restic`

``` /bash
wget https://github.com/vmware-tanzu/velero/releases/download/v1.11.0/velero-v1.11.0-linux-amd64.tar.gz | tar xvzf -
mv velero /usr/local/bin && chmod velero +x
# Si le choix de l'installation du serveur velero a été fait en mode non sécurisé
alias velero='velero --insecure-skip-tls-verify'
```

#### Installation du CLI Restic

Restic est le logiciel de sauvegarde par snapshot filesystem quand le
CSI du provider ne supporte pas le snapshot.

##### Récupération du mot de passe restic lors de l\'installation du serveur Restic

Ce mot de passe sera demandé à chaque commande restic

``` /bash
oc extract secret/velero-restic-credentials -n openshift-adp --to=-
# ou
oc get -n openshift-adp secrets velero-restic-credentials -o jsonpath="{.data.repository-password}" | base64 -d
```

##### Installation

``` /bash
wget https://github.com/restic/restic/releases/download/v0.15.2/restic_0.15.2_linux_amd64.bz2 -O restic | bzip2 -d -
mv restic /usr/local/bin && chmod restic +x
```

#### Installation du CLI AWS

##### Installation

``` /bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" | unzip -
mv aws /usr/local/bin && chmod aws +x
```

##### Configuration

``` /bash
export AWS_CA_BUNDLE=/tmp/okd-dev.der
alias aws='aws --endpoint https://s3-openshift-storage.apps.orchidee.okd-dev.abes.fr'
# ou bien en dernier recours si on n a pas récupéré le certificat root du routeur d openshift:
alias aws='aws --endpoint https://s3-openshift-storage.apps.orchidee.okd-dev.abes.fr --no-verify-ssl'
```

### Configuration au niveau d\'OKD

#### Création du **backingstore**

C\'est la partie qui va physiquement contenir les objets sauvegardés

-   Backups
-   Snapshots
-   Restic

**ODF** en a déjà créé un par défaut avec Nooba, sur fond de classe
RADOS Ceph (RGW)

``` /bash
oc get backingstores.noobaa.io -n openshift-storage 
NAME                           TYPE            PHASE   AGE
noobaa-default-backing-store   s3-compatible   Ready   12d
```

Pour simplifier la démarche, nous allons utiliser ce backingstore par
défaut (même s\'il est possible d\'en créer d\'autres à partir de
nouveaux buckets claim)

#### Création de la Bucket Class

``` /bash
oc apply -f <<EOF
apiVersion: noobaa.io/v1alpha1
kind: BucketClass
metadata:
  labels:
    app: noobaa
  name: noobaa-default-bucket-class
  namespace: openshift-storage
spec:
  placementPolicy:
    tiers:
    - backingStores:
      - noobaa-default-backing-store
EOF
```

On peut également créer cette même **Bucket Class** depuis l\'UI:

Storage -\> Data Foundation -\> Bucket Class

On vérifie:

``` /bash
oc -n openshift-storage get bucketclasses.noobaa.io 
NAME                          PLACEMENT                                                        NAMESPACEPOLICY   QUOTA   PHASE   AGE
noobaa-default-bucket-class   {"tiers":[{"backingStores":["noobaa-default-backing-store"]}]} 
```

#### Création de l\'**Object Bucket Claim**

``` /bash
oc apply -f - <<EOF
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: migstorage
  namespace: openshift-storage
  labels:
    app: noobaa
    bucket-provisioner: openshift-storage.noobaa.io-obc
    noobaa-domain: openshift-storage.noobaa.io
spec:
  additionalConfig:
    bucketclass: noobaa-default-bucket-class
  bucketName: migstorage-588a21b0-edd7-4400-a39b-3508ab083a10
  generateBucketName: migstorage
  objectBucketName: obc-openshift-storage-migstorage
  storageClassName: openshift-storage.noobaa.io
EOF
```

On vérifie:

``` /bash
oc get -n openshift-storage objectbucketclaim migstorage -o yaml
```

#### Modes de sauvegardes

##### manifests/volume

-   manifests: Dans tous les cas de figure le backup sauvegarde les
    **manifests** liés au deployment choisi.
-   volumes: Les volumes persistants (PV) sont aussi sauvegardés, mais
    seulement ceux qui sont attachés à un deployment par un **pvc**

##### sauvegarde des volumes en mode FSB vs CSI

-   FSB: c\'est le mode utilisé pour le backup des volumes créés par des
    storage class ne supportant pas les snapshots. C\'est notre cas avec
    `ovirt-csi`
-   CSI: Il existe deux types de CSI:

       * Ceux qui sont natifs à velero et qui supportent les grands fournisseurs de cloud (''AWS'', ''GCP'', ''Azure'', etc...). La liste complète est ici: https://velero.io/plugins/
       * Ceux qui exploitent les propriétés CSI des drivers qui supportent le snapshot (ce n'est pas le cas de ''ovirt-csi''), notamment: ''nfs.csi.k8s.io'', et les drivers fournis par ODF via rook: ''openshift-storage.rbd.csi.ceph.com'' et ''openshift-storage.cephfs.csi.ceph.com''

Au moment de la première version de ce document, la version de OADP
fournie avec OKD 4.12 était la **1.1.8**. La version de velero embarquée
avec OADP 1.1.8 était la 1.9 et ne comprenait pas le même niveau d\'API.

-   `restic` seul était utilisé pour le backup des volumes ne supportant
    pas le snapshot CSI pour le mode **FSB**. L\'option à apporter dans
    le lancement du backup est soit:

      * dans le manifest dpa: ''defaultVolumesToRestic: true''
      * avec le CLI velero: ''--default-volumes-to-restic''

-   `restic` ou `kopia` dans la version OADP 1.3.1/velero 1.12
    -   dans le manifest dpa: `defaultVolumesToFSBackup: true`
    -   avec le CLI velero: `--default-volumes-to-fs-backup=true`

#### Installation du logiciel Velero \< 1.9

**C\'est la version installée par défaut par OADP 1.1. Cette partie
reste comme mémoire mais elle n\'est plus utilisée depuis l\'upgrade
vers velero 1.3.1** La configuration se fait grâce à la définition du
`CR` **DataProtectionApplication**. On peut définir le fichier
directement en mode yaml ou bien depuis l\'interface web:

1.  Click Operators → Installed Operators and select the OADP Operator.
2.  Under Provided APIs, click Create instance in the
    DataProtectionApplication box.
3.  Click YAML View and update the parameters of the
    DataProtectionApplication manifest:

Il faut préciser dès l\'installation de Velero si on veut l\'installer
en mode sécurisé, si ce n\'est pas fait, il faudra détruire l\'objet
`DataProtectionApplication` et le recréer avec le certificat pour que le
container se redéploie avec la prise en compte du certificat root.

#### Création du secret

\* création d\'un fichier `cloud-credentials`

``` /bash
cat <<EOF > credential-velero && oc create secret generic cloud-credentials2 -n openshift-adp --from-file cloud=credential-velero && rm -f credential-velero
[default]
aws_access_key_id=key
aws_secret_access_key=key
EOF
```

``` /bash
oc create secret generic cloud-credentials -n openshift-adp --from-file cloud=credentials-velero
```

##### mode non sécurisé

Si `insecureSkipTLSVerify=false`, alors SSL/TLS est activé De plus,
contrairement à ce que la documentation officielle velero indique, il
n\'est possible de préciser l\'option `--cacert` en cli, mais il est
quand même possible de renseigner le certificat CA dans la conf velero:

``` /bash
velero client config set cacert=/tmp/ingress.pem
```

``` /bash
oc apply -f - <<EOF  
apiVersion: oadp.openshift.io/v1alpha1
kind: DataProtectionApplication
metadata:
  name: velero-sample
  namespace: openshift-adp
spec:
  backupLocations:
  - velero:
      config:
        insecureSkipTLSVerify: "false"
        profile: default
        region: minio
        s3ForcePathStyle: "true"
        s3Url: https://s3-openshift-storage.apps.orchidee.okd-dev.abes.fr
      credential:
        key: cloud
        name: cloud-credentials
      default: true
      objectStorage:
        bucket: migstorage-588a21b0-edd7-4400-a39b-3508ab083a10
        prefix: velero
      provider: aws
  configuration:
    restic:
      enable: true
    velero:
      defaultPlugins:
      - openshift
      - aws
      - kubevirt
      - csi
  defaultVolumesToRestic: true
  snapshotLocations:
  - velero:
      config:
        profile: default
        region: us-west-2
      provider: aws
EOF
```

##### mode sécurisé

``` /bash
oc apply -f - <<EOF  
apiVersion: oadp.openshift.io/v1alpha1
kind: DataProtectionApplication
metadata:
  name: velero-sample
  namespace: openshift-adp
spec:
  backupLocations:
  - velero:
      config:
        insecureSkipTLSVerify: "false"
        profile: default
        region: minio
        s3ForcePathStyle: "true"
        s3Url: https://s3-openshift-storage.apps.orchidee.okd-dev.abes.fr
      credential:
        key: cloud
        name: cloud-credentials
      default: true
      objectStorage:
        bucket: migstorage-588a21b0-edd7-4400-a39b-3508ab083a10
        caCert: 
        prefix: velero
      provider: aws
  configuration:
    restic:
      enable: true
    velero:
      defaultPlugins:
      - openshift
      - aws
      - kubevirt
      - csi
  defaultVolumesToRestic: true
  snapshotLocations:
  - velero:
      config:
        profile: default
        region: us-west-2
      provider: aws
EOF
```

#### Vérification du bon fonctionnement de Velero

Toutes les manipulations se font dans le namespace `openshift-adp` On
peut cependant configurer velero pour qu\'il prenne en compte ce
namespace par défaut au lieu de `velero`

``` /bash
velero client config set namespace=openshift-adp
cat /home/nblanchet/.config/velero/config.json
{"namespace":"openshift-adp"}
```

``` /bash
oc get all -n openshift-adp
NAME                                                    READY   STATUS    RESTARTS   AGE
pod/openshift-adp-controller-manager-5d47dfd7cc-6gcp2   1/1     Running   0          8d
pod/restic-9645w                                        1/1     Running   0          8d
pod/restic-9pl4m                                        1/1     Running   0          8d
pod/restic-ftpfl                                        1/1     Running   0          8d
pod/velero-6984c689f5-x97z2                             1/1     Running   0          8d

NAME                                                       TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE
service/openshift-adp-controller-manager-metrics-service   ClusterIP   172.30.170.135   <none>        8443/TCP   390d
service/openshift-adp-velero-metrics-svc                   ClusterIP   172.30.210.63    <none>        8085/TCP   378d

NAME                    DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR   AGE
daemonset.apps/restic   3         3         3       3            3           <none>          378d

NAME                                               READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/openshift-adp-controller-manager   1/1     1            1           390d
deployment.apps/velero                             1/1     1            1           378d

NAME                                                          DESIRED   CURRENT   READY   AGE
replicaset.apps/openshift-adp-controller-manager-5d47dfd7cc   1         1         1       8d
replicaset.apps/openshift-adp-controller-manager-bdc95f5c9    0         0         0       217d
replicaset.apps/velero-5858d6dfcb                             0         0         0       217d
replicaset.apps/velero-6984c689f5                             1         1         1       8d
replicaset.apps/velero-6c6fcf574b                             0         0         0       377d
replicaset.apps/velero-6dfddf4574                             0         0         0       252d
replicaset.apps/velero-7887bf7c9c                             0         0         0       378d
replicaset.apps/velero-7dbc47ff6d                             0         0         0       335d
```

On vérifie que la conf est cohérente au niveau des CR

``` /bash
oc get -n openshift-adp backupstoragelocations.velero.io
oc get -n openshift-adp backupstoragelocations.velero.io velero-sample-1 -o json | jq '.spec'
{
  "config": {
    "insecureSkipTLSVerify": "false",
    "profile": "default",
    "region": "minio",
    "s3ForcePathStyle": "true",
    "s3Url": "https://s3-openshift-storage.apps.orchidee.okd-dev.abes.fr"
  },
  "credential": {
    "key": "cloud",
    "name": "cloud-credentials"
  },
  "default": true,
  "objectStorage": {
    "bucket": "migstorage-588a21b0-edd7-4400-a39b-3508ab083a10",
    "caCert": "cert",
    "prefix": "velero"
  },
  "provider": "aws"
}
```

Le client velero se connecte par défaut à l\'environnement k8s défini
par la variable `$KUBECONFIG`. On peut aussi forcer cet environnement
avec l\'option `--kubeconfig`

``` /bash
oc -n openshift-adp exec velero-6984c689f5-x97z2 -- /velero snapshot-location get
velero backup-location get -n openshift-adp
NAME              PROVIDER   BUCKET/PREFIX                                            PHASE       LAST VALIDATED                   ACCESS MODE   DEFAULT
velero-sample-1   aws        migstorage-588a21b0-edd7-4400-a39b-3508ab083a10/velero   Available   2024-05-29 18:55:31 +0200 CEST   ReadWrite     true
```

``` /bash
oc get -n openshift-adp volumesnapshotlocations.velero.io velero-sample-1 -o json | jq '.spec'
{
  "config": {
    "profile": "default",
    "region": "us-west-2"
  },
  "provider": "aws"
}
```

``` /bash
oc -n openshift-adp exec velero-6984c689f5-x97z2 -- /velero snapshot-location get
velero snapshot-location get -n openshift-adp
NAME              PROVIDER
velero-sample-1   aws
```

#### Effectuer un backup Velero FSB

-   On sélectionne les objets à sauvegarder au moyen de filtres
    appropriés

Pour rappel, dans cette partie, on n\'utilise uniquement que le mode FSB
défini dans le CR `dpa`, l\'option `--default-volumes-to-fs-backup` est
donc inutile mais est là pour mémoire.

``` /bash
# par sélection de label
velero backup create movies --selector io.kompose.network/movies-docker-test-default=true -n openshift-adp (--default-volumes-to-fs-backup=true)
# par namespace
velero backup create movies --include-namespaces=movies-docker-ceph -n openshift-adp (--default-volumes-to-fs-backup=true)
```

version sans filtres:

``` /bash
oc apply -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: <backup>
  labels:
    velero.io/storage-location: default
  namespace: openshift-adp
spec:
  csiSnapshotTimeout: 10m0s
  defaultVolumesToRestic: true
  includedNamespaces:
  - movies-docker-ceph
  itemOperationTimeout: 4h0m0s
  storageLocation: velero-sample2-1
  volumeSnapshotLocations:
  - velero-sample2-1
EOF
```

version avec `labelSelector`

``` /bash
oc apply -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: <backup>
  labels:
    velero.io/storage-location: default
  namespace: openshift-adp
spec:
  csiSnapshotTimeout: 10m0s
  includedNamespaces:
  - '*'
  labelSelector:
    matchLabels:
      io.kompose.network/movies-docker-test-default: "true"
  itemOperationTimeout: 4h0m0s
  storageLocation: velero-sample2-1
  volumeSnapshotLocations:
  - velero-sample2-1
EOF
```

     * Vérification de l'état de la sauvegarde

``` /bash
velero backup describe movies -n openshift-adp
velero backup logs movies -n openshift-adp
velero backup get movies
NAME     STATUS      ERRORS   WARNINGS   CREATED                          EXPIRES   STORAGE LOCATION   SELECTOR
movies   Completed   0        0          2024-05-29 19:46:36 +0200 CEST   29d       velero-sample-1    io.kompose.network/movies-docker-test-default=true
oc get podvolumebackups.velero.io  -n openshift-adp --sort-by='{metadata.creationTimestamp}'
movies60-vvtff   Completed   8h        movies-docker-ceph   movies-wikibase-wdqs-7f65d75f4d-p6jrp   movies-wikibase-wdqs-claim0    s3:http://ocs-storagecluster-cephobjectstore-openshift-storage.apps.orchidee.okd-dev.abes.fr/tutu2-3e90e44e-a940-454e-a891-587d13472302/velero/restic/movies-docker-ceph   kopia           velero-sample-1    8h
```

``` /bash
velero backup describe movies62 --details
...
Backup Item Operations:
                Operation for volumesnapshots.snapshot.storage.k8s.io movies-docker-ceph/velero-movies-wikibase-mysql-claim3-wpb6x:
                  Backup Item Action Plugin:  velero.io/csi-volumesnapshot-backupper
                  Operation ID:               movies-docker-ceph/velero-movies-wikibase-mysql-claim3-wpb6x/2024-06-14T14:13:52Z
                  Items to Update:
                            volumesnapshots.snapshot.storage.k8s.io movies-docker-ceph/velero-movies-wikibase-mysql-claim3-wpb6x
                  Phase:    Completed
                  Created:  2024-06-14 16:13:52 +0200 CEST
                  Started:  2024-06-14 16:13:52 +0200 CEST
                Operation for volumesnapshotcontents.snapshot.storage.k8s.io /snapcontent-2463af57-dfd2-4a50-8841-42e3e518e8ee:
                  Backup Item Action Plugin:  velero.io/csi-volumesnapshotcontent-backupper
                  Operation ID:               snapcontent-2463af57-dfd2-4a50-8841-42e3e518e8ee/2024-06-14T14:13:52Z
                  Items to Update:
                            volumesnapshotcontents.snapshot.storage.k8s.io /snapcontent-2463af57-dfd2-4a50-8841-42e3e518e8ee
                  Phase:    Completed
                  Created:  2024-06-14 16:13:52 +0200 CEST
                  Started:  2024-06-14 16:13:52 +0200 CEST
...
```

-   Vérification du contenu des fichiers

``` /bash
export AWS_ACCESS_KEY_ID="key"; export AWS_SECRET_ACCESS_KEY="key"; aws s3 ls s3://tutu2-3e90e44e-a940-454e-a891-587d13472302/ --recursive --endpoint http://ocs-storagecluster-cephobjectstore-openshift-storage.apps.orchidee.okd-dev.abes.fr | sort
2024-06-14 12:58:55    1112117 velero/restic/movies-docker-ceph/data/97/9735f40a7d8778f4af65b5f467de2233e0dcada6f9e01aa446f6e8e2f5c6cc5c
2024-06-14 12:58:55       1232 velero/restic/movies-docker-ceph/index/4eca95163a14b77e8d766c3c0d8d8f296ae03729e6e431a499523e947dd79e8c
2024-06-14 12:58:55      27273 velero/restic/movies-docker-ceph/data/e0/e0e87d85179da5f117392afb92f9ca2e08cb3bdd93cd5a288a7dad1306de1027
2024-06-14 12:58:55        382 velero/restic/movies-docker-ceph/snapshots/ce5ff1181f80b9913d154475105c8585e744aa2fad52aed7e41bbf9581bcefa3
2024-06-14 12:58:56      10941 velero/backups/movies56/movies56-logs.gz
2024-06-14 12:58:56         27 velero/backups/movies56/movies56-csi-volumesnapshotcontents.json.gz
2024-06-14 12:58:56         29 velero/backups/movies56/movies56-csi-volumesnapshots.json.gz
2024-06-14 12:58:56       9893 velero/backups/movies56/movies56.tar.gz
2024-06-14 12:58:58         29 velero/backups/movies56/movies56-csi-volumesnapshotclasses.json.gz
2024-06-14 12:58:58         49 velero/backups/movies56/movies56-results.gz
2024-06-14 12:58:58        990 velero/backups/movies56/movies56-podvolumebackups.json.gz
2024-06-14 12:59:00         27 velero/backups/movies56/movies56-itemoperations.json.gz
2024-06-14 12:59:00         29 velero/backups/movies56/movies56-volumesnapshots.json.gz
2024-06-14 12:59:00        326 velero/backups/movies56/movies56-resource-list.json.gz
2024-06-14 12:59:01       3238 velero/backups/movies56/velero-backup.json
```

On distingue bien deux parties;

-   la partie sauvegarde du volume `restic`

``` /bash
2024-06-14 12:58:55    1112117 velero/restic/movies-docker-ceph/data/97/9735f40a7d8778f4af65b5f467de2233e0dcada6f9e01aa446f6e8e2f5c6cc5c
2024-06-14 12:58:55       1232 velero/restic/movies-docker-ceph/index/4eca95163a14b77e8d766c3c0d8d8f296ae03729e6e431a499523e947dd79e8c
2024-06-14 12:58:55      27273 velero/restic/movies-docker-ceph/data/e0/e0e87d85179da5f117392afb92f9ca2e08cb3bdd93cd5a288a7dad1306de1027
2024-06-14 12:58:55        382 velero/restic/movies-docker-ceph/snapshots/ce5ff1181f80b9913d154475105c8585e744aa2fad52aed7e41bbf9581bcefa3
```

-   La partie sauvegardes des manifests:

``` /bash
2024-06-14 12:58:56      10941 velero/backups/movies56/movies56-logs.gz
2024-06-14 12:58:56         27 velero/backups/movies56/movies56-csi-volumesnapshotcontents.json.gz
2024-06-14 12:58:56         29 velero/backups/movies56/movies56-csi-volumesnapshots.json.gz
2024-06-14 12:58:56       9893 velero/backups/movies56/movies56.tar.gz
2024-06-14 12:58:58         29 velero/backups/movies56/movies56-csi-volumesnapshotclasses.json.gz
2024-06-14 12:58:58         49 velero/backups/movies56/movies56-results.gz
2024-06-14 12:58:58        990 velero/backups/movies56/movies56-podvolumebackups.json.gz
2024-06-14 12:59:00         27 velero/backups/movies56/movies56-itemoperations.json.gz
2024-06-14 12:59:00         29 velero/backups/movies56/movies56-volumesnapshots.json.gz
2024-06-14 12:59:00        326 velero/backups/movies56/movies56-resource-list.json.gz
2024-06-14 12:59:01       3238 velero/backups/movies56/velero-backup.json
```

#### Effectuer un backup Velero CSI

<https://docs.okd.io/latest/backup_and_restore/application_backup_and_restore/installing/oadp-backup-restore-csi-snapshots.html>

C\'est le plugin `csi` qui active cette fonctionnalité. Bien que
présent, il n\'était pas activé à cause de l\'option
`defaultVolumesToFsBackup: true` qui forçait le FSB. L\'avantage du
snapshot CSI est de pouvoir capturer une image fixe du volume
contrairement à ne sauvegarde plate qui peut varier entre le début et la
fin de la sauvegarde.

On peut optionnellement définir un `snapshotLocation` différent de
restic, ainsi qu\'un profil de credential différent.

La mise en oeuvre est la même que précédemment:

``` /bash
oc apply -f - <<EOF  
apiVersion: oadp.openshift.io/v1alpha1
kind: DataProtectionApplication
metadata:
  name: velero-sample
  namespace: openshift-adp
spec:
  backupLocations:
  - velero:
      config:
        insecureSkipTLSVerify: "false"
        profile: default
        region: minio
        s3ForcePathStyle: "true"
        s3Url: https://s3-openshift-storage.apps.orchidee.okd-dev.abes.fr
      credential:
        key: cloud
        name: cloud-credentials
      default: true
      objectStorage:
        bucket: migstorage-588a21b0-edd7-4400-a39b-3508ab083a10
        prefix: velero
      provider: aws
  configuration:
    restic:
      enable: true
    velero:
      defaultPlugins:
      - openshift
      - aws
      - kubevirt
      - csi
      defaultVolumesToRestic: false
  snapshotLocations:
  - velero:
      config:
        profile: default
        region: us-west-2
      provider: aws
EOF
```

La sauvegarde se fait alors par snapshot et non plus par fichiers plats.
On peut cependant désactiver cette fonction soit dans le CR
`DataProtectionApplication` soit dans le CR `backup` avec:

``` /bash
''defaultVolumesToRestic: true''
```

     * Vérification de l'état de la sauvegarde

``` /bash
oc get volumesnapshotcontents.snapshot.storage.k8s.io --sort-by='{metadata.creationTimestamp}' -n openshift-adp
snapcontent-2463af57-dfd2-4a50-8841-42e3e518e8ee   true         0             Retain           openshift-storage.rbd.csi.ceph.com      ocs-storagecluster-rbdplugin-snapclass      name-51e498eb-f8d4-410c-9a0c-7d13e4abc3d7   ns-51e498eb-f8d4-410c-9a0c-7d13e4abc3d7   6h13m
```

Si on regarde aux fichiers générés dans la target bucket, on ne trouve
cette fois que la sauvegarde des manifests. En effet, les snapshots des
volumes restent sur l\'environnement k8s d\'origine, dans l\'objet
`volumesnapshotcontents`

``` /bash
export AWS_ACCESS_KEY_ID="key"; export AWS_SECRET_ACCESS_KEY="key"; aws s3 ls s3://tutu2-3e90e44e-a940-454e-a891-587d13472302/ --recursive --endpoint http://ocs-storagecluster-cephobjectstore-openshift-storage.apps.orchidee.okd-dev.abes.fr | sort
2024-06-14 16:13:52      11413 velero/backups/movies62/movies62-logs.gz
2024-06-14 16:13:54         29 velero/backups/movies62/movies62-podvolumebackups.json.gz
2024-06-14 16:13:54         29 velero/backups/movies62/movies62-volumesnapshots.json.gz
2024-06-14 16:13:54        389 velero/backups/movies62/movies62-itemoperations.json.gz
2024-06-14 16:13:54        430 velero/backups/movies62/movies62-resource-list.json.gz
2024-06-14 16:13:54        488 velero/backups/movies62/movies62-csi-volumesnapshotclasses.json.gz
2024-06-14 16:13:54         49 velero/backups/movies62/movies62-results.gz
2024-06-14 16:13:54        789 velero/backups/movies62/movies62-csi-volumesnapshots.json.gz
2024-06-14 16:13:54        853 velero/backups/movies62/movies62-csi-volumesnapshotcontents.json.gz
2024-06-14 16:13:57      11126 velero/backups/movies62/movies62.tar.gz
2024-06-14 16:13:57       3546 velero/backups/movies62/velero-backup.json
```

### Velero 1.3

##### Mise à jour

``` /bash
oc get subscriptions.operators.coreos.com -n openshift-adp -o yaml
oc patch --type='json' subscriptions  redhat-oadp-operator -p '[{"op": "replace", "path": "/spec/channel", "value": 'stable-1.3'}]' -n openshift-adp
oc get subscriptions.operators.coreos.com -n openshift-adp -o json redhat-oadp-operator | jq '.spec.channel|="stable-1.3"' | oc apply -f -
```

Cette version de velero apporte deux fonctionnalités principales:

-   le choix entre `restic` ou `kopia` pour le backup de volumes par
    filesystem (**FSB**) ou **CSI** si le driver csi supporte les
    snapshots.
-   le mode **Data Mover** qui s\'appuie uniquement sur `kopia`.

##### Kopia

Dans le manifest `DataProtectionApplication`, on définit `kopia` comme
logiciel de backup à la place de `restic`. La syntaxe qui ne s\'appuie
plus uniquement sur `restic` mais sur un `nodeAgent` agnostique, repose
sur les même principes que la version 1.1:

      * dans le manifest dpa: 
        * ''FSB'': ''defaultVolumesToFSBackup: true''
        * ''CSI'': ''defaultVolumesToFSBackup: false''
      * avec le CLI velero: 
          * ''FSB'': ''--default-volumes-to-fs-backup=true''
          * ''CSI'': ''--default-volumes-to-fs-backup=false''

``` /bash
oc apply -f - <<EOF  
apiVersion: oadp.openshift.io/v1alpha1
kind: DataProtectionApplication
metadata:
  name: velero-sample
  namespace: openshift-adp
spec:
  backupLocations:
  - velero:
      config:
        insecureSkipTLSVerify: "true"
        profile: default
        region: minio
        s3ForcePathStyle: "true"
        s3Url: http://ocs-storagecluster-cephobjectstore-openshift-storage.apps.orchidee.okd-dev.abes.fr
      credential:
        key: cloud
        name: cloud-credentials2
      default: true
      objectStorage:
        bucket: tutu2-3e90e44e-a940-454e-a891-587d13472302
        caCert: cert
        prefix: velero
      provider: aws
  configuration:
    nodeAgent:
      enable: true
      uploaderType: kopia
    velero:
      defaultPlugins:
      - openshift
      - aws
      - kubevirt
      - csi
      defaultVolumesToFSBackup: true
      featureFlags:
      - EnableCSI
  snapshotLocations:
  - velero:
      config:
        profile: default
        region: minio
      provider: aws
EOF
```

Puis on peut lancer le backup:

``` /bash
#FSB
velero backup create velero-sample --default-volumes-to-fs-backup --include-namespaces=movies-docker-ceph -n openshift-adp
#CSI
velero backup create velero-sample --default-volumes-to-fs-backup=false --include-namespaces=movies-docker-ceph -n openshift-adp
```

``` /bash
oc apply -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: <backup>
  labels:
    velero.io/storage-location: default
  namespace: openshift-adp
spec:
  defaultVolumesToFsBackup: true
  csiSnapshotTimeout: 10m0s
  includedNamespaces:
  - movies-docker-ceph
  itemOperationTimeout: 4h0m0s
  storageLocation: velero-sample2-1
  volumeSnapshotLocations:
  - velero-sample2-1
EOF
```

On observe les mêmes résultats:

``` /bash
oc get podvolumebackups.velero.io  -n openshift-adp --sort-by='{metadata.creationTimestamp}'
oc get volumesnapshotcontents.snapshot.storage.k8s.io --sort-by='{metadata.creationTimestamp}' -n openshift-adp
```

##### Data mover

C\'est la nouveauté de cette version. Par défaut, les snapshots des
volumes `CSI` sont stockés sur OKD/Openshift dans l\'objet
`volumesnapshotcontents`, ce qui peut rendre la sauvegarde fragile si on
venait à perdre le cluster. Cette fonctionnalité permet de copier les
snapshots sur un backing store de stockage de type objet comme de simple
fichiers.

Pour ce faire, il faut

-   dans le `dpa`:

      * ''.spec.configuration.nodeAgent.uploaderType: kopia''
      * optionnellement et si on veut que ce soit le  comportement par défaut, rajouter l'option ''.spec.configuration.velero.defaultSnapshotMoveData: true''

-   dans le volumeSnapshotClass: s\'assurer que le label
    `metadata.labels.velero.io/csi-volumesnapshot-class: "true"` est
    bien renseigné:

``` /bash
oc get volumesnapshotclasses.snapshot.storage.k8s.io 
NAME                                        DRIVER                                  DELETIONPOLICY   AGE
csi-nfs-snapclass                           nfs.csi.k8s.io                          Delete           32d
ocs-storagecluster-cephfsplugin-snapclass   openshift-storage.cephfs.csi.ceph.com   Delete           406d
ocs-storagecluster-rbdplugin-snapclass      openshift-storage.rbd.csi.ceph.com      Delete           406d
oc label volumesnapshotclasses ocs-storagecluster-cephfsplugin-snapclass velero.io/csi-volumesnapshot-class="true"
```

``` /bash
velero backup create velero-sample --snapshot-move-data --include-namespaces=movies-docker-ceph -n openshift-adp --snapshot-move-data 
```

``` /bash
oc apply -f - <<EOF
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: <backup>
  labels:
    velero.io/storage-location: default
  namespace: openshift-adp
spec:
  defaultVolumesToFsBackup: false
  snapshotMoveData: true
  csiSnapshotTimeout: 10m0s
  includedNamespaces:
  - movies-docker-ceph
  itemOperationTimeout: 4h0m0s
  storageLocation: velero-sample2-1
  volumeSnapshotLocations:
  - velero-sample2-1
EOF
```

Vérification des snapshots:
<https://docs.okd.io/latest/backup_and_restore/application_backup_and_restore/installing/oadp-backup-restore-csi-snapshots.html>

``` /bash
velero backup describe movies63 --details
...
Backup Item Operations:
  Operation for persistentvolumeclaims movies-docker-ceph/movies-wikibase-mysql-claim3:
    Backup Item Action Plugin:  velero.io/csi-pvc-backupper
    Operation ID:               du-4cf3c2a8-acae-4074-8ba5-3670eca7f5b1.586aa15f-599c-4e8c70f53
    Items to Update:
                           datauploads.velero.io openshift-adp/movies63-znfb5
    Phase:                 Completed
    Progress:              1506139247 of 1506139247 complete (Bytes)
    Progress description:  Completed
    Created:               2024-06-14 17:47:20 +0200 CEST
    Started:               2024-06-14 17:47:20 +0200 CEST
    Updated:               2024-06-14 17:47:37 +0200 CEST
...
```

``` /bash
oc get  datauploads.velero.io  -n openshift-adp movies63-znfb5 -o yaml
apiVersion: velero.io/v2alpha1
kind: DataUpload
metadata:
  creationTimestamp: "2024-06-14T15:47:20Z"
  generateName: movies63-
  generation: 7
  labels:
    velero.io/accepted-by: orchidee-ccbm8-worker-zhgql
    velero.io/async-operation-id: du-4cf3c2a8-acae-4074-8ba5-3670eca7f5b1.586aa15f-599c-4e8c70f53
    velero.io/backup-name: movies63
    velero.io/backup-uid: 4cf3c2a8-acae-4074-8ba5-3670eca7f5b1
    velero.io/pvc-uid: 586aa15f-599c-4e8c-83f6-015fd7bf1405
  name: movies63-znfb5
  namespace: openshift-adp
  ownerReferences:
  - apiVersion: velero.io/v1
    controller: true
    kind: Backup
    name: movies63
    uid: 4cf3c2a8-acae-4074-8ba5-3670eca7f5b1
  resourceVersion: "613342660"
  uid: 783c290b-af60-4029-9674-b34a3d63921a
spec:
  backupStorageLocation: velero-sample-1
  csiSnapshot:
    snapshotClass: ""
    storageClass: ocs-storagecluster-ceph-rbd
    volumeSnapshot: velero-movies-wikibase-mysql-claim3-rz8zq
  operationTimeout: 10m0s
  snapshotType: CSI
  sourceNamespace: movies-docker-ceph
  sourcePVC: movies-wikibase-mysql-claim3
status:
  completionTimestamp: "2024-06-14T15:47:37Z"
  node: orchidee-ccbm8-worker-9pg8j
  path: /host_pods/e21766a1-5f51-418f-afb1-489c46099cc4/volumes/kubernetes.io~csi/pvc-75d159f9-8ca3-481d-a3d4-cc3608d56568/mount
  phase: Completed
  progress:
    bytesDone: 1506139247
    totalBytes: 1506139247
  snapshotID: be9bed8e30b21ecb10ce8dc682bfbdc1
  startTimestamp: "2024-06-14T15:47:20Z
```

De plus, on voit bien à présent qu\'aucun `volumeSnaphotContents` n\'est
généré:

``` /bash
oc get volumesnapshotcontents.snapshot.storage.k8s.io --sort-by='{metadata.creationTimestamp}' -n openshift-adp
```

Ce qui confirme bien que les fichiers de snapshots ont bien été
transférés sur le bucket cible.

``` /bash
2024-06-14 17:47:21      11273 velero/backups/movies63/movies63-logs.gz
2024-06-14 17:47:22         29 velero/backups/movies63/movies63-podvolumebackups.json.gz
2024-06-14 17:47:22         29 velero/backups/movies63/movies63-volumesnapshots.json.gz
2024-06-14 17:47:22         49 velero/backups/movies63/movies63-results.gz
2024-06-14 17:47:24        326 velero/backups/movies63/movies63-resource-list.json.gz
2024-06-14 17:47:26         29 velero/backups/movies63/movies63-csi-volumesnapshotcontents.json.gz
2024-06-14 17:47:26         29 velero/backups/movies63/movies63-csi-volumesnapshots.json.gz
2024-06-14 17:47:27         29 velero/backups/movies63/movies63-csi-volumesnapshotclasses.json.gz
2024-06-14 17:47:36        143 velero/kopia/movies-docker-ceph/xn3_1766d77834043d8d3028d5882c0d8596-s3474572057443e35129-c1
2024-06-14 17:47:36        143 velero/kopia/movies-docker-ceph/xn3_32f90df80df2289d37808d618d88535e-s35fd80c593099092129-c1
2024-06-14 17:47:36       4298 velero/kopia/movies-docker-ceph/q6f2616dddff33e3387601852c685fcd9-s35fd80c593099092129
2024-06-14 17:47:36       4298 velero/kopia/movies-docker-ceph/q983c2aa6c38fafbaafde7e3d7f4a8492-s3474572057443e35129
2024-06-14 17:47:37       2358 velero/kopia/movies-docker-ceph/_log_20240614154736_8bcf_1718380056_1718380057_1_952d78db457628ad35bd9838d3bc9546
2024-06-14 17:47:41        398 velero/backups/movies63/movies63-itemoperations.json.gz
2024-06-14 17:47:43      10947 velero/backups/movies63/movies63.tar.gz
2024-06-14 17:47:43       3420 velero/backups/movies63/velero-backup.json
```

Contrairement à un backup sans l\'option `Data Mover`, on retrouve bien
des fichiers de volumes `kopia`.

``` /bash
oc get -o json datauploads -n openshift-adp | jq '.items[]|{(.metadata.name): {(.spec.sourcePVC): (.spec.csiSnapshot.storageClass)}}' 
{
  "movies21-27zl7": {
    "movies-wikibase-mysql-claim6": "nfs-csi3"
  }
}
{
  "movies21-c5n25": {
    "movies-wikibase-mysql-claim0": "ocs-storagecluster-cephfs"
  }
}
{
  "movies21-tbksj": {
    "movies-wikibase-mysql-claim5": "nfs-csi3"
  }
}
{
  "movies21-v2crv": {
    "movies-wikibase-mysql-claim7": "nfs-csi4"
  }
}
{
  "movies21-zm7n5": {
    "movies-wikibase-mysql-claim1": "ocs-storagecluster-cephfs"
  }
}
{
  "movies22-48v7b": {
    "movies-wikibase-mysql-claim1": "ocs-storagecluster-cephfs"
  }
}
{
  "movies22-dqfqr": {
    "movies-wikibase-mysql-claim5": "nfs-csi3"
  }
}
{
  "movies22-jll4t": {
    "movies-wikibase-mysql-claim0": "ocs-storagecluster-cephfs"
  }
}
{
  "movies22-mt5bc": {
    "movies-wikibase-mysql-claim7": "nfs-csi4"
  }
}
{
  "movies22-pm2kq": {
    "movies-wikibase-mysql-claim6": "nfs-csi3"
  }
}
```
