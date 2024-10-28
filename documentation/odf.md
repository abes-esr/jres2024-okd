# Open Data Foundation (ODF)

## Introduction

Lors d\'une Installation IPI, c\'est le driver CSI du provider cloud qui
est le le système de stockage par défaut. Dans notre cas, il s\'agit de
`ovirt-csi`. Mais ce driver peut manquer de certaines fonctionnalités
telles que les **snapshots** et certains droits d\'accès au stockage,
notamment le `RWX`. Dans notre cas c\'est la limitation du driver
`ovirt-csi`.

Redhat fournit OpenDataFoundation qui est un logiciel cloud intégré à
son offre OpenShift, disponible sous forme d\'opérateur. Les détails
techniques de l\'installation se trouvent sur cette page: [Drivers
CSI](/okd/drivers_csi). Ce logiciel crée une couche d\'abstraction entre
le driver CSI par défaut et **Ceph** qui est le stockage distribué
évolutif et redondant. Le stockage Ceph est finalement présenté à
l\'utilisateur sous différents modes:

-   Filesystem: CephFS, CephNFS(désactuvé par défaut)
-   Block: RADOS Block Device (RBD)
-   Objet: RADOS GateWAy (RGW) et MultiCloud Gateway (MCG)

Les données à manipuler sur le cluster OKD se trouvent dans le namespace
`openshift-storage`. Pour éviter de préciser le namespace à chaque
commande `-n openshift-storage`, on rentre dans le projet:

``` bash
oc project openshift-storage
oc project
```

### CephFS

La `storageClass` installé par ODF est **ocs-storagecluster-cephfs** On
l\'utilise pour le partage de fichier à l\'instar de NFS, c\'est la
raison pour laquelle CephNFS est désactivé par défaut. Le client natif
est donc Ceph.

### Block

La `storageClass` installé par ODF est **ocs-storagecluster-rbd** On
l\'utilise pour des images ou des bases de données.

### Objet

Le mode objet est la particularité de Ceph et c\'est tout le fond du
sujet. Il est décliné en deux sous-modes d\'utilisation:

1.  Multicloud Object Gateway: **openshift-storage.noobaa.io**
2.  RADOS Object Gateway: **ocs-storagecluster-ceph-rgw**

Dans les deux cas de figure, l\'accès aux données se fait par une
connexion **S3 compatible**, dont le client le plus utilisé est celui
d\'Amazon qui est à l\'origine du protocole (fermé) **aws**. Dans le cas
de RGW, on peut aussi consommer les données avec le client Swift de
Ceph.

On utilise le mode objet pour le stockage de petites quantités de
données unitaires, typiquement, des média, ou de la sauvegarde.

## StorageSystem

L\'objet pilier d\'ODF est `StorageSystem`. Il n\'est pas défini par
défaut après installation, il faut donc le créer manuellement. Il y a
deux modes de fonctionnement:

1.  interne: on utilisera un driver CSI d\'OKD, par défaut celui du
    provider cloud (ovirt-csi dans notre cas)
2.  externe: ODF prévoit la possibilité de se connecter à un cluster de
    stockage pré-existant (Ceph ou autre).

**NB**: On ne peut créer qu\'un seul Storage System interne, même si
l\'interface nous permet de créer d\'autres Storage System externes.

On choisit de dédier ou pas des hôtes au fonctionnement des pods avec la
fonction `tainted`.

Les hôtes (vms dans notre cas) fonctionnent par 3 pour répondre aux
exigences de système distribué de Ceph, et Redhat nous conseille pour un
fonctionnement correct d\'attribuer au minimum 34GB de RAM pour chacun
des 3hôtes et 14 vCPUs.

``` bash
oc describe -n openshift-storage storageclusters.ocs.openshift.io
oc get nodes
*NAME                          STATUS   ROLES                  AGE    VERSION
orchidee-ccbm8-master-0       Ready    control-plane,master   454d   v1.25.7+eab9cc9
orchidee-ccbm8-master-1       Ready    control-plane,master   454d   v1.25.7+eab9cc9
orchidee-ccbm8-master-2       Ready    control-plane,master   454d   v1.25.7+eab9cc9
orchidee-ccbm8-master-30      Ready    control-plane,master   391d   v1.25.7+eab9cc9
orchidee-ccbm8-worker-9pg8j   Ready    worker                 454d   v1.25.7+eab9cc9
orchidee-ccbm8-worker-cb2lg   Ready    infra,worker           383d   v1.25.7+eab9cc9
orchidee-ccbm8-worker-hqwhs   Ready    infra,worker           383d   v1.25.7+eab9cc9
orchidee-ccbm8-worker-hxmn4   Ready    infra,worker           383d   v1.25.7+eab9cc9
orchidee-ccbm8-worker-v55b4   Ready    worker                 454d   v1.25.7+eab9cc9
orchidee-ccbm8-worker-zhgql   Ready    worker                 454d   v1.25.7+eab9cc9
```

``` bash
oc get -n openshift-storage CephObjectStore
```

### Exposition du service de stockage Ceph

Le stockage Ceph est alors accessible sous forme de service
**s3-compatible**, implémentant ainsi la majorité des APIs du protocole
propriétaire d\'Amazon. On manipule donc le stockage Ceph avec le client
officiel **s3**.

## CLI AWS

### Installation

``` bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" | unzip -
mv aws /usr/local/bin && chmod aws +x
```

### Mise à jour

curl \"<https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip>\" -o
\"awscliv2.zip\" unzip awscliv2.zip sudo ./aws/install \--bin-dir
/usr/local/bin \--install-dir /usr/local/aws-cli \--update aws
\--version

### Configuration Globale

#### Mode direct

-   Non sécurisé

``` bash
aws --endpoint http://endpoint <cmd>
```

-   Sécurisé sans certificat

``` bash
aws --endpoint https://endpoint --no-verify-ssl <cmd> 
```

-   Sécurisé avec le certificat ingress d\'OKD généré par défaut

Récupérer le certificat root:

``` bash
oc get -o json secret router-certs-default -n openshift-ingress | jq -r '.data|map_values(@base64d)|to_entries[]|select(.key=="tls.crt").value' > /tmp/ingress.crt
```

``` bash
aws --endpoint https://endpoint --ca-bundle=/tmp/ingress.crt <cmd>
# ou bien en exportant la variable
export AWS_CA_BUNDLE=/tmp/ingress.crt
```

#### Avec fichier de config

-   Création du fichier **credentials**

``` bash
cat ~/.aws/credentials
[admin]
aws_access_key_id = ''
aws_secret_access_key = ''
```

-   Création du fichier **config**

``` bash
cat ~/.aws/config
[profile admin]
endpoint_url = https://endpoint
ca_bundle = /tmp/ingress.crt
region = Montpellier
```

**NB**: le fichier config doit contenir au moins une region pour éviter
l\'authentification du client auprès des serveurs d\'Amazon. Cependant,
on peut désactiver cette fonctionnalité en exportant la variable:

``` bash
export AWS_EC2_METADATA_DISABLED=true
```

## Le mode Objet

### Rados Gateway (RGW)

RADOS est le daemon qui permet à OKD de présenter objets Ceph sous forme
d\'une API S3 (Amazon) ou Swift (Openstack) compatible. C\'est l\'unique
passerelle entre Ceph et le client installé par ODF. Rook.io est
l\'orchestrateur qui déploie Ceph et rados et les présente sous les 3
formes:

-   file: cephfs
-   block: cephrbd
-   object: RGW

![](/files/selection_401.png)

#### Installation du client radosgw

Le client RADOS n\'est pas installé par défaut pour contrôler le cluster
Ceph puisque RedHat pousse à l\'utilisation de MCGW pour le cloud
hybride. Pour contrôler le backend ceph, il faut donc activer `radosgw`
de cette façon:

``` bash
oc patch OCSInitialization ocsinit -n openshift-storage --type json --patch  '[{ "op": "replace", "path": "/spec/enableCephTools", "value": true }]'
```

L\'exécution se fait donc dans un container auquel on accède ainsi:

``` bash
oc rsh -n openshift-storage $(oc get pod -n openshift-storage -l app=rook-ceph-tools -o jsonpath='{.items[0].metadata.name}')
# ou bien:
oc -n openshift-storage rsh $(oc get pods -n openshift-storage -l app=rook-ceph-tools -o name)
```

on peut à partir de là consulter ou créer différentes ressources du
backend Ceph:

``` bash
$ radosgw-admin user create --display-name="Your user" --uid=your-user
$ radosgw-admin user info --uid your-user

$ radosgw-admin buckets list
[
    "rook-ceph-bucket-checker-8104169c-60b4-4458-b224-8041031d9718",
    "nb.1683297491248.apps.orchidee.okd-dev.abes.fr"
]
```

A noter qu\'on peut également (non recommandé) exécuter dans ce
container la commande `ceph` pour superviser quelques commandes natives
au cluster.

``` bash
sh-4.4$ ceph -s
  cluster:
    id:     b654dd82-706d-4b72-9ba6-c6a70b9c2d1b
    health: HEALTH_OK
 
  services:
    mon: 3 daemons, quorum a,b,c (age 2w)
    mgr: a(active, since 2w)
    mds: 1/1 daemons up, 1 hot standby
    osd: 3 osds: 3 up (since 2w), 3 in (since 13M)
    rgw: 1 daemon active (1 hosts, 1 zones)
 
  data:
    volumes: 1/1 healthy
    pools:   12 pools, 353 pgs
    objects: 92.73k objects, 9.3 GiB
    usage:   26 GiB used, 1.5 TiB / 1.5 TiB avail
    pgs:     353 active+clean
 
  io:
    client:   1.6 KiB/s rd, 7.0 KiB/s wr, 2 op/s rd, 0 op/s wr
```

#### Configuration par défaut de RGW par ODF

-   Utilisateur **noobaa-ceph-objectstore-user**

L\'utilisateur `noobaa-ceph-objectstore-userr` est spécialement créé
pour RGW par ODF.

``` bash
radosgw-admin user info --uid noobaa-ceph-objectstore-user | jq '.keys[]'
{
  "user": "noobaa-ceph-objectstore-user",
  "access_key": "",
  "secret_key": ""
}
```

ou avec `oc`

``` bash
oc get cephobjectstoreusers.ceph.rook.io -n openshift-storage
NAME                                     PHASE
noobaa-ceph-objectstore-user             Ready
ocs-storagecluster-cephobjectstoreuser   Ready
prometheus-user                          Ready
```

C\'est cet utilisateur qu\'utilise ODF pour créér le **backingStore**
par défaut `noobaa-default-backing-store` avec le secret
`rook-ceph-object-user-ocs-storagecluster-cephobjectstore-noobaa-ceph-objectstore-user`

-   secret
    **rook-ceph-object-user-ocs-storagecluster-cephobjectstore-noobaa-ceph-objectstore-user**

``` bash
oc get -o json secrets rook-ceph-object-user-ocs-storagecluster-cephobjectstore-noobaa-ceph-objectstore-user -n openshift-storage | jq -r '.data|map_values(@base64d)'
{
  "AccessKey": "",
  "Endpoint": "https://rook-ceph-rgw-ocs-storagecluster-cephobjectstore.openshift-storage.svc:443",
  "SecretKey": ""
}
```

-   Bucket **nb.1683297491248.apps.orchidee.okd-dev.abes.fr**

``` bash
oc get -n openshift-storage  backingstores.noobaa.io  -o json noobaa-default-backing-store | jq -r '.spec.s3Compatible.targetBucket'
```

-   un service: **rook-ceph-rgw-ocs-storagecluster-cephobjectstore**

``` bash
oc  get svc -n openshift-storage
```

-   une route:
    **ocs-storagecluster-cephobjectstore-openshift-storage.apps.orchidee.okd-dev.abes.fr**

``` bash
oc get route -n openshift-storage
NAME                                 HOST/PORT                                                                            PATH   SERVICES                                           PORT         TERMINATION          WILDCARD
ocs-storagecluster-cephobjectstore   ocs-storagecluster-cephobjectstore-openshift-storage.apps.orchidee.okd-dev.abes.fr          rook-ceph-rgw-ocs-storagecluster-cephobjectstore   <all>                             None
```

Cette route sera utilisée comme `endpoint` dans le fichier de
confguration de `aws`

-   une storageClass **ocs-storagecluster-ceph-rgw**

``` bash
oc get sc
```

-   Un objectStore **ocs-storagecluster-cephobjectstore**

``` bash
oc get cephobjectstores.ceph.rook.io  -n openshift-storage
NAME                                 PHASE
ocs-storagecluster-cephobjectstore   Connected
```

#### Configuration du client aws

-   fichier de credentials

``` bash
vi ~/.aws/credentials
[noobaa-ceph-objectstore-user]
aws_access_key_id = 
aws_secret_access_key = 
```

-   fichier de config

La configuration se fait uniquement en **http** et non en **https**

``` bash
vi ~/.aws/config
[profile noobaa-ceph-objectstore-user]
endpoint_url = http://ocs-storagecluster-cephobjectstore-openshift-storage.apps.orchidee.okd-dev.abes.fr
region = Montpellier
```

#### utilisation cu client aws

``` bash
aws s3api list-buckets  --profile noobaa-ceph-objectstore-user 
{
    "Buckets": [
        {
            "Name": "nb.1683297491248.apps.orchidee.okd-dev.abes.fr",
            "CreationDate": "2023-05-05T14:38:16.695000+00:00"
        }
    ],
    "Owner": {
        "DisplayName": "my display name",
        "ID": "noobaa-ceph-objectstore-user"
    }
}
```

#### comparaison des clients

-   `radosgw-admin` sert a gérer les utilisateurs, à consuter mais pas
    de créer des **buckets**
-   `aws` permet de créer des buckets à partir d\'utilisateurs existants
    et fait le lien entre les deux.

#### Création d\'un utilisateur et d\'un bucket associés

-   Création d\'un utilisateur avec **radosgw-admin**

On peut cependant créer d\'autres utilisateurs et buckets associés, mais
ceux créés par défaut par ODF peuvent suffire.

La création d\'un utilisateur entraîne la génération d\'une
**access_key** et d\'une **secret_key** associée. Ce sont les données
qui seront demandées plus tard pour authentifier le **bucket**.

``` bash
radosgw-admin user info --uid  your-user | jq '.keys[]'
{
  "user": "your-user",
  "access_key": "",
  "secret_key": ""
}
```

Pour obtenir tous les mots de passe d\'un coup:

``` bash
$ for i in $(radosgw-admin user list | jq -r '.[]'); do echo $i;radosgw-admin user info --uid $i | jq '.keys[]'
```

#### Création d\'une bucket

-   Avec le client **aws** ( lié à l\'utilisateur précédemment créé)

``` bash
aws s3api create-bucket --bucket your-user --profile your-user
{
    "Buckets": [
        {
            "Name": "your-user",
            "CreationDate": "2024-05-22T14:55:34.244000+00:00"
        }
    ],
    "Owner": {
        "DisplayName": "Your user",
        "ID": "your-user"
    }
}
```

-   avec **oc**

On peut également créer une nouvelle bucket en créant un
objectBuketClaimn en s\'appuyant sur la storageClass
**ocs-storagecluster-ceph-rgw**

``` bash
oc apply -f - <<EOF
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: ceph-bucket
  namespace: default
spec:
  bucketName:
  generateBucketName: ceph-bucket
  storageClassName: ocs-storagecluster-ceph-rgw
EOF
```

``` bash
oc get obc -n default ceph-bucket 
NAME          STORAGE-CLASS                 PHASE   AGE
ceph-bucket   ocs-storagecluster-ceph-rgw   Bound   19h
```

``` bash
oc get ObjectBucketClaim ceph-bucket -n default -o jsonpath='{.spec.bucketName}'
oc get ObjectBucketClaim ceph-bucket -n default -o json | jq -r '.spec.bucketName'
ceph-bucket-6088e63f-00d6-4d73-9067-616ef1243624
```

#### backingStore par défaut dans ODF

Le backingStore est l\'objet k8s qui permet définir une **bucket**
servant à stocker les objets. On la définit par 3 éléments:

-   endpoint
-   secret
-   targetBucket

Celui installé par défaut par ODF est **noobaa-default-backing-store**.
Si le nom contient **noobaa** fait partie de ce nom, c\'est simplement
que le backingStore a été créé au moyen de la commande noobaa, ce qui
rend le backingStore géré par **noobaa**

``` bash
oc  get backingstores.noobaa.io -n openshift-storage noobaa-default-backing-store -o json | jq '.metadata.labels'
{
  "app": "noobaa"
}
```

``` bash
oc get backingstores.noobaa.io -n openshift-storage
NAME                           TYPE            PHASE   AGE
noobaa-default-backing-store   s3-compatible   Ready   398d
```

et pointe par défaut vers la route interne du RGW (et non la MCG)

``` bash
oc  get backingstores.noobaa.io -n openshift-storage noobaa-default-backing-store -o json | jq '.spec'
{
  "s3Compatible": {
    "endpoint": "https://rook-ceph-rgw-ocs-storagecluster-cephobjectstore.openshift-storage.svc:443",
    "secret": {
      "name": "rook-ceph-object-user-ocs-storagecluster-cephobjectstore-noobaa-ceph-objectstore-user",
      "namespace": "openshift-storage"
    },
    "signatureVersion": "v4",
    "targetBucket": "nb.1683297491248.apps.orchidee.okd-dev.abes.fr"
  },
  "type": "s3-compatible"
}
```

A noter que la bucket **nb.1683297491248.apps.orchidee.okd-dev.abes.fr**
est générée lors de l\'installation et n\'est donc pas générée par un
**objectBucketClaim** comme il convient de le faire de manière
classique.

C\'est la raison pour laquelle on ne la retrouve pas lorsqu\'on la
recherche:

``` bash
oc get obc -A -o json | jq -r '.items[].spec.bucketName'
bucket--26847890-4912-4b6f-8076-f59b49c53f57
ceph-bucket-6088e63f-00d6-4d73-9067-616ef1243624
loulou-768ae91b-e543-4343-9a16-14275e7aeff5
tutu2-3e90e44e-a940-454e-a891-587d13472302
tutu3-596982b9-be5d-4b25-961c-140a91dd6742
movies-docker-ceph-722ee512-df61-4d19-a8b9-efffa669abf7
migstorage-588a21b0-edd7-4400-a39b-3508ab083a10
tutu-e50058f9-a891-43a0-b20a-3d757f80d941
```

De même la classe associée au backingStore
**noobaa-default-backing-store** est celle par défaut
**noobaa-default-bucket-class**

``` bash
{
  "placementPolicy": {
    "tiers": [
      {
        "backingStores": [
          "noobaa-default-backing-store"
        ]
      }
    ]
  }
}
```

### MultiCloud Gateway (MCG)

**MCG** est la passerelle par défaut fournie par **ODF** pour accéder au
backend de stokage \*\* Ceph\*\*.

C\'est une interface unique permettant de se connecter à différents
modes de stockage cloud au moyen de **backingStores**:

-   AWS S3
-   S3 Compatible (RGW)
-   PVC
-   Google Cloud Storage
-   Azure Blob
-   IBM COS

L\'avantage du MCG par rapport à RGW est non seulement qu\'il soit multi
provider mais aussi qu\'il permet d\'agréger les backingStore dans deux
modes:

-   spread: équivalent du raid 0
-   mirror: équivalent du raid 1

#### Noobaa

Le client utilisé pour configurer et consulter un **backingStore** est
`noobaa`

-   Installation de noobaa

``` bash
NOOBAA_VERSION=v2.0.10
curl -Lo noobaa https://github.com/noobaa/noobaa-operator/releases/download/$NOOBAA_VERSION/noobaa-linux-$NOOBAA_VERSION
chmod +x noobaa
sudo install noobaa /usr/local/bin/
```

**noobaa** permet de recueillir un état du service objet ODF à partir du
namespace `openshift-storage`

``` bash
noobaa status -n openshift-storage
admin@noobaa.io password : ""

#-----------------#
#- STS Addresses -#
#-----------------#

ExternalDNS : [https://sts-openshift-storage.apps.orchidee.okd-dev.abes.fr]
ExternalIP  : []
NodePorts   : [https://10.35.212.157:30203]
InternalDNS : [https://sts.openshift-storage.svc:443]
InternalIP  : [https://172.30.80.113:443]
PodPorts    : [https://10.131.2.14:7443]

#----------------#
#- S3 Addresses -#
#----------------#

ExternalDNS : [https://s3-openshift-storage.apps.orchidee.okd-dev.abes.fr]
ExternalIP  : []
NodePorts   : [https://10.35.212.157:30937]
InternalDNS : [https://s3.openshift-storage.svc:443]
InternalIP  : [https://172.30.239.146:443]
PodPorts    : [https://10.131.2.14:6443]

#------------------#
#- S3 Credentials -#
#------------------#

AWS_ACCESS_KEY_ID     : 
AWS_SECRET_ACCESS_KEY : 

#------------------#
#- Backing Stores -#
#------------------#

NAME                           TYPE            TARGET-BUCKET                                    PHASE   AGE            
noobaa-default-backing-store   s3-compatible   nb.1683297491248.apps.orchidee.okd-dev.abes.fr   Ready   1y23d3h0m35s   
rgw-resource                   s3-compatible   toto-f4c07e14-6a6c-42e4-be0f-177e213c3a2d        Ready   1y19d1h7m17s   
your-user                      s3-compatible   your-user                                        Ready   5d2h16m44s     

#--------------------#
#- Namespace Stores -#
#--------------------#

No namespace stores found.

#------------------#
#- Bucket Classes -#
#------------------#

NAME                          PLACEMENT                                                        NAMESPACE-POLICY   QUOTA   PHASE   AGE            
noobaa-default-bucket-class   {"tiers":[{"backingStores":["noobaa-default-backing-store"]}]}   null               null    Ready   1y23d3h0m35s   

#-------------------#
#- NooBaa Accounts -#
#-------------------#

No noobaa accounts found.

#-----------------#
#- Bucket Claims -#
#-----------------#

NAMESPACE           NAME         BUCKET-NAME                                       STORAGE-CLASS                 BUCKET-CLASS                  PHASE   
openshift-storage   migstorage   migstorage-588a21b0-edd7-4400-a39b-3508ab083a10   openshift-storage.noobaa.io   noobaa-default-bucket-class   Bound
```

On retrouve les mêmes identifiants S3 générés par ODF avec oc:

``` bash
oc get secrets -n openshift-storage noobaa-admin -o json | jq -r '.data|map_values(@base64d)'
{
  "AWS_ACCESS_KEY_ID": "",
  "AWS_SECRET_ACCESS_KEY": "",
  "email": "admin@noobaa.io",
  "password": "",
  "system": "noobaa"
}
```

#### Configuration de MCG avec un obc tutu

Contrairement à la bucketClass et au backingStore
**noobaa-default-backing-store** précédemment créé par défaut ODF, il
n\'y a pas d\'exemple de configuration de bucketClass/backingStore
pointant vers des providers extérieurs.

Nous allons donc procéder ainsi:

-   Création d\'un objectBucketClaim

Dans un premier temps, nous allons créer un bucket qui n\'est pas relié
à une bucketClass

<https://www.ibm.com/docs/en/storage-fusion/2.6?topic=claim-dynamic-object-bucket>

``` bash
oc apply -f - <<EOF
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: tutu
  namespace: openshift-storage
spec:
  bucketName:
  generateBucketName: tutu
  objectBucketName: obc-openshift-storage-tutu
  storageClassName: openshift-storage.noobaa.io
EOF
```

<https://www.ibm.com/docs/en/storage-fusion/2.6?topic=obc-creating-object-bucket-claim-using-command-line-interface>

``` bash
noobaa obc create tutu -n openshift-storage
```

-   Récupération des objets `bucket` et `secrets` générés

``` bash
oc get ObjectBucketClaim tutu -n openshift-storage -o json | jq -r '.spec.bucketName'
tutu-e50058f9-a891-43a0-b20a-3d757f80d941
```

``` bash
oc get -n openshift-storage secrets tutu -o json | jq -r '.data|map_values(@base64d)'
{
  "AWS_ACCESS_KEY_ID": "",
  "AWS_SECRET_ACCESS_KEY": ""
}
```

``` bash
noobaa obc status tutu -n openshift-storage

ObjectBucketClaim info:
  Phase                  : Bound
  ObjectBucketClaim      : kubectl get -n openshift-storage objectbucketclaim tutu
  ConfigMap              : kubectl get -n openshift-storage configmap tutu
  Secret                 : kubectl get -n openshift-storage secret tutu
  ObjectBucket           : kubectl get objectbucket obc-openshift-storage-tutu
  StorageClass           : kubectl get storageclass openshift-storage.noobaa.io
  BucketClass            : kubectl get -n openshift-storage bucketclass tutu-bucket-class

Connection info:
  BUCKET_HOST            : s3.openshift-storage.svc
  BUCKET_NAME            : tutu-e50058f9-a891-43a0-b20a-3d757f80d941
  BUCKET_PORT            : 443
  AWS_ACCESS_KEY_ID      : 
  AWS_SECRET_ACCESS_KEY  : 

Shell commands:
  AWS S3 Alias           : alias s3='AWS_ACCESS_KEY_ID='' AWS_SECRET_ACCESS_KEY='' aws s3 --no-verify-ssl --endpoint-url https://10.35.212.157:30937'

Bucket status:
  Name                   : tutu-e50058f9-a891-43a0-b20a-3d757f80d941
  Type                   : REGULAR
  Mode                   : OPTIMAL
  ResiliencyStatus       : OPTIMAL
  QuotaStatus            : QUOTA_NOT_SET
  Num Objects            : 0
  Data Size              : 0.000 B
  Data Size Reduced      : 0.000 B
  Data Space Avail       : 1.000 PB
  Num Objects Avail      : 9007199254740991
  
```

-   Création d\'un backingStore utilisant le secret et la targetBucket
    prédécemment générés

<https://www.ibm.com/docs/en/storage-fusion/2.6?topic=multicloud-creating-s3-compatible-object-gateway-backingstore>

``` bash
noobaa backingstore create s3-compatible tutu --access-key='' --secret-key='' --target-bucket tutu-e50058f9-a891-43a0-b20a-3d757f80d941 -n openshift-storage
```

``` bash
oc apply -f - <<EOF
apiVersion: noobaa.io/v1alpha1
kind: BackingStore
metadata:
  labels:
    app: noobaa
  name: tutu
  namespace: openshift-storage
spec:
  s3Compatible:
    endpoint: https://s3.openshift-storage.svc:443
    secret:
      name: tutu
      namespace: openshift-storage
    targetBucket: tutu
  type: s3-compatible
EOF
```

-   Création d\'une bucketClass qui va comprendre un seul membre

<https://www.ibm.com/docs/en/storage-fusion/2.6?topic=mdhmb-creating-bucket-classes-mirror-data-using-mcg-command-line-interface>

``` bash
noobaa bucketclass create placement-bucketclass tutu-bucket-class --backingstores=tutu
```

``` bash
oc apply -f - <<EOF
apiVersion: noobaa.io/v1alpha1
kind: BucketClass
metadata:
  name: tutu-bucket-class
  labels:
    app: noobaa
spec:
  placementPolicy:
    tiers:
      - backingStores:
          - tutu
        placement: Spread
EOF
```

-   vérification

``` bash
noobaa backingstore status tutu  -n openshift-storage
INFO[0000] ✅ Exists: BackingStore "tutu"                
INFO[0000] ✅ Exists: Secret "noobaa-account-toto"       
INFO[0000] ✅ BackingStore "tutu" Phase is Ready         

# BackingStore spec:
s3Compatible:
  endpoint: https://s3.openshift-storage.svc:443
  secret:
    name: noobaa-account-toto
    namespace: openshift-storage
  targetBucket: tutu
type: s3-compatible

```

on obtient la même chose avec `oc`

``` bash
oc get -n openshift-storage backingstores.noobaa.io -o json tutu | jq '.spec'
```

-   Secret **tutu**

``` bash
oc get -n openshift-storage secrets tutu -o json | jq -r '.data|map_values(@base64d)'
{
  "AWS_ACCESS_KEY_ID": "",
  "AWS_SECRET_ACCESS_KEY": ""
}
```

-   endPoint \*\* <https://s3.openshift-storage.svc:443>\*\*

A noter que le endpoint contrairement à RGW se présente sous la forme
interne, à savoir, `service.namespace.svc`

-   targetBucket **tutu-e50058f9-a891-43a0-b20a-3d757f80d941**
-   un service **s3**

``` bash
oc get svc -n openshift-storage
NAME                                               TYPE           CLUSTER-IP       EXTERNAL-IP   PORT(S)                                                    AGE
TCP,443/TCP                                             388d
s3                                                 LoadBalancer   172.30.239.146   <pending>     80:30321/TCP,443:30937/TCP,8444:30063/TCP,7004:32220/TCP   388d
```

-   une route **s3-openshift-storage.apps.orchidee.okd-dev.abes.fr**

``` bash
oc get route -n openshift-storage
NAME    HOST/PORT      PATH   SERVICES     PORT         TERMINATION          WILDCARD
s3     s3-openshift-storage.apps.orchidee.okd-dev.abes.fr     s3          s3-https 
```

#### Accès par le client

-   On récupère toutes les informations de connexion via

``` bash
noobaa obc status tutu -n openshift-storage
</code

  * Sans certificat

<code bash>
aws --endpoint https://s3-openshift-storage.apps.orchidee.okd-dev.abes.fr --no-verify-ssl
```

-   Connexion avec le client:

#### Mode direct

-   Non sécurisé

``` bash
aws --endpoint http://endpoint <cmd>
```

-   Sécurisé sans certificat

``` bash
aws --endpoint https://s3-openshift-storage.apps.orchidee.okd-dev.abes.fr --no-verify-ssl <cmd> 
```

-   Sécurisé avec le certificat ingress d\'OKD généré par défaut

Récupérer le certificat root:

``` bash
oc get -o json secret router-certs-default -n openshift-ingress | jq -r '.data|map_values(@base64d)|to_entries[]|select(.key=="tls.crt").value' > /tmp/ingress.crt
```

``` bash
aws --endpoint https://s3-openshift-storage.apps.orchidee.okd-dev.abes.fr --ca-bundle=/tmp/ingress.crt <cmd>
# ou bien en exportant la variable
export AWS_CA_BUNDLE=/tmp/ingress.crt
```

#### Avec fichier de config

-   Création du fichier **credentials**

``` bash
cat ~/.aws/credentials
[admin]
aws_access_key_id = ""
aws_secret_access_key = ""
```

-   Création du fichier **config**

``` bash
cat ~/.aws/config
[profile admin]
endpoint_url = https://s3-openshift-storage.apps.orchidee.okd-dev.abes.fr
ca_bundle = /tmp/ingress.crt
region = Montpellier
```

``` bash
aws --ca-bundle=/tmp/ingress.crt s3api list-buckets --endpoint https://s3-openshift-storage.apps.orchidee.okd-dev.abes.fr --profile admin 
# ou bien en exportant la variable
export AWS_CA_BUNDLE=/tmp/ingress.crt
```

#### Mirrored MCG

On peut dans une BucketClass donnée sélectionner des backingStores pour
sécuriser les données. Pour ce faire, il faut créer un nouveau
objectBucketClaim à qui on va attribuer cette classe.

-   Création ou mise à jour de la classe:

``` bash
noobaa backingstore list -n openshift-storage
NAME                           TYPE            TARGET-BUCKET                                    PHASE   AGE             
nat                            s3-compatible   nat-cf3a745b-ac64-440f-b6e4-02531d6d41b8         Ready   1d4h45m19s      
noobaa-default-backing-store   s3-compatible   nb.1683297491248.apps.orchidee.okd-dev.abes.fr   Ready   1y34d7h25m21s   
test                           s3-compatible   test-c0127d64-b478-43d1-9566-53deda2caf4f        Ready   7h34m38s        
tutu                           s3-compatible   tutu                                             Ready   10d11h16m24s    
```

``` bash
noobaa bucketclass create placement-bucketclass mirror --backingstores=test,tutu --placement Mirror
```

``` bash
oc apply -f <<EOF
apiVersion: noobaa.io/v1alpha1
kind: BucketClass
metadata:
  labels:
    app: noobaa
  name: mirror
  namespace: openshift-storage
spec:
  placementPolicy:
    tiers:
    - backingStores:
      - tutu
      - test
      placement: Mirror
```

-   Création de l\'obc avec la bucketClass

``` bash
noobaa obc create  mirrored-bucket --bucketclass=mirror
```

``` bash
oc get obc/tutu -n openshift-storage -o json | jq  '.spec+={"additionalConfig":{"bucketclass":"mirror"}}'
```

-   Test d\'écriture

``` bash
oc get ObjectBucketClaim mirror -n openshift-storage -o json | jq -r '.spec.bucketName'
mirror-38ba3f67-32c5-4b3f-a2b7-175f6f5ea050
```

On uploade un fichier sur la bucket qu\'on vient de créer:

``` bash
export AWS_ACCESS_KEY_ID=""; export AWS_SECRET_ACCESS_KEY=""; aws s3 cp tito s3://mirror-38ba3f67-32c5-4b3f-a2b7-175f6f5ea050/ --endpoint https://s3-openshift-storage.apps.orchidee.okd-dev.abes.fr
```

    export AWS_ACCESS_KEY_ID=""; export AWS_SECRET_ACCESS_KEY=""; aws s3api list-objects-v2 --bucket mirror-38ba3f67-32c5-4b3f-a2b7-175f6f5ea050 --endpoint https://s3-openshift-storage.apps.orchidee.okd-dev.abes.fr
    {
        "Contents": [
            {
                "Key": "tito",
                "LastModified": "2024-06-07T14:59:04+00:00",
                "ETag": "\"d14b74f5f6b586d28237f5af15d4bc49\"",
                "Size": 178219,
                "StorageClass": "STANDARD"
            }
        ],
        "RequestCharged": null
    }
    # ou bien
    export AWS_ACCESS_KEY_ID=""; export AWS_SECRET_ACCESS_KEY=""; aws s3 ls s3://mirror-38ba3f67-32c5-4b3f-a2b7-175f6f5ea050 --endpoint https://s3-openshift-storage.apps.orchidee.okd-dev.abes.fr --recursive
    2024-06-07 16:59:04     178219 tito

On a vu précédemment que la bucketClass faisait référence à un mirroir
de deux backingStorage `tutu` et `test`

``` bash
oc get bucketclasses.noobaa.io -n openshift-storage ezfc -o json | jq '.spec'
noobaa -n openshift-storage bucketclass status mirrored-bucket
INFO[0000] ✅ Exists: BucketClass "ezfc"                 
INFO[0000] ✅ BucketClass "ezfc" Phase is Ready          

# BucketClass spec:
placementPolicy:
  tiers:
  - backingStores:
    - tutu
    - test
    placement: Mirror
```

On va vérifier que le même objet ya été créé dans les deux buckets:

``` bash
export AWS_ACCESS_KEY_ID=""; export AWS_SECRET_ACCESS_KEY=""; aws s3 ls --recursive s3://nat-cf3a745b-ac64-440f-b6e4-02531d6d41b8 --endpoint https://s3-openshift-storage.apps.orchidee.okd-dev.abes.fr
2024-06-07 13:42:15      97478 noobaa_blocks/6661ef5484b58f0029bcfda5/blocks_tree/0fd.blocks/6662f2170ca8bd000d9970fd
2024-06-07 15:08:23      97478 noobaa_blocks/6661ef5484b58f0029bcfda5/blocks_tree/158.blocks/666306470ca8bd000d997158
2024-06-08 00:37:09       1024 noobaa_blocks/6661ef5484b58f0029bcfda5/blocks_tree/other.blocks/_test_store_perf
2024-06-07 16:56:32         36 noobaa_blocks/6661ef5484b58f0029bcfda5/usage
```

``` bash
export AWS_ACCESS_KEY_ID=""; export AWS_SECRET_ACCESS_KEY=""; aws s3api list-object-versions --bucket nat-cf3a745b-ac64-440f-b6e4-02531d6d41b8 --endpoint https://s3-openshift-storage.apps.orchidee.okd-dev.abes.fr
{
    "Versions": [
        {
            "ETag": "\"c4f0b7cd427535367bb28fba77e77c23\"",
            "Size": 97478,
            "StorageClass": "STANDARD",
            "Key": "noobaa_blocks/6661ef5484b58f0029bcfda5/blocks_tree/0fd.blocks/6662f2170ca8bd000d9970fd",
            "VersionId": "null",
            "IsLatest": true,
            "LastModified": "2024-06-07T11:42:15+00:00",
            "Owner": {
                "DisplayName": "NooBaa",
                "ID": "123"
            }
        },
        {
            "ETag": "\"4f91141880e725c28c322fcec81098c7\"",
            "Size": 97478,
            "StorageClass": "STANDARD",
            "Key": "noobaa_blocks/6661ef5484b58f0029bcfda5/blocks_tree/158.blocks/666306470ca8bd000d997158",
            "VersionId": "null",
            "IsLatest": true,
            "LastModified": "2024-06-07T13:08:23+00:00",
            "Owner": {
                "DisplayName": "NooBaa",
                "ID": "123"
            }
        },
        {
            "ETag": "\"98d55e60db6132f93fdc5315f2929616\"",
            "Size": 1024,
            "StorageClass": "STANDARD",
            "Key": "noobaa_blocks/6661ef5484b58f0029bcfda5/blocks_tree/other.blocks/_test_store_perf",
            "VersionId": "null",
            "IsLatest": true,
            "LastModified": "2024-06-07T22:37:09+00:00",
            "Owner": {
                "DisplayName": "NooBaa",
                "ID": "123"
            }
        },
        {
            "ETag": "\"259c0c7791bbd48bc445f349f89d748d\"",
            "Size": 36,
            "StorageClass": "STANDARD",
            "Key": "noobaa_blocks/6661ef5484b58f0029bcfda5/usage",
            "VersionId": "null",
            "IsLatest": true,
            "LastModified": "2024-06-07T14:56:32+00:00",
            "Owner": {
                "DisplayName": "NooBaa",
                "ID": "123"
            }
        }
    ],
    "RequestCharged": null
}
```

-   Taille de ma bucket

``` bash
export AWS_ACCESS_KEY_ID=""; export AWS_SECRET_ACCESS_KEY=""; aws s3api list-objects --bucket tutu2-3e90e44e-a940-454e-a891-587d13472302 --endpoint http://ocs-storagecluster-cephobjectstore-openshift-storage.apps.orchidee.okd-dev.abes.fr | jq '[.Contents[].Size]|add|./(1024*1024*1024)' 
2.240389700047672
#ou bien
export AWS_ACCESS_KEY_ID=""; export AWS_SECRET_ACCESS_KEY=""; aws s3api list-objects --bucket tutu2-3e90e44e-a940-454e-a891-587d13472302 --endpoint http://ocs-storagecluster-cephobjectstore-openshift-storage.apps.orchidee.okd-dev.abes.fr  --query "[sum(Contents[].Size), length(Contents[])]"
```

### ObjectBucketClaim

Un `objectBucketClaim` est un objet kubernetes de stockage en mode objet
qui une fois créé génère plusieurs variables nécessaire à l\'accès de la
bucket:

-   AWS_ACCESS_KEY_ID
-   AWS_SECRET_ACCESS_KEY
-   BUCKET_HOST
-   BUCKET_NAME
-   BUCKET_PORT

Comme vu précédemment, il y a deux façons de créer un object bucket:

-   par RGW

C\'est le mode le plus direct puisqu\'il n\'y a ni de `bucketClass` à
configurer, ni de `backingStore`.

Il s\'appuie sur le la `storageClass` `ocs-storagecluster-ceph-rgw` qui
est définie à l\'installation d\'ODF.

``` bash
oc apply -f - <<EOF
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: ceph-bucket
  namespace: default
spec:
  bucketName:
  generateBucketName: ceph-bucket
  storageClassName: ocs-storagecluster-ceph-rgw
EOF
```

Le résultat est en deux parties:

l\'objectBucketClaim:

``` bash
oc get obc -n default ceph-bucket 
NAME          STORAGE-CLASS                 PHASE   AGE
ceph-bucket   ocs-storagecluster-ceph-rgw   Bound   19h
```

le secret pour y accéder:

``` bash
oc get secrets -n default ceph-bucket
NAME          TYPE     DATA   AGE
ceph-bucket   Opaque   2      27d
```

``` bash
oc extract secrets/ceph-bucket -n default --to=-
# AWS_ACCESS_KEY_ID
""
# AWS_SECRET_ACCESS_KEY
""```

-   par MCG

Ce mode permet sans limites d\'ajouter différents cloud providers et de
pouvoir étendre l\'objet bucket sur deux modes différents: `spread` et
`mirror` grâce à la définition d\'une `bucketClass`, par défaut
`noobaa-default-bucket-class`. Cette bucketClass n\'est ni `spread` ni
`mirror`

``` bash
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
```

La `bucketClass` s\'appuit elle-même sur différents `backingStore` qui
doivent être définis au préalable. Le backingStore par défaut est
`noobaa-default-backing-store`

``` bash
oc apply -f - <<EOF 
apiVersion: noobaa.io/v1alpha1
kind: BackingStore
metadata:
  annotations:
    rgw: ""
  labels:
    app: noobaa
  name: noobaa-default-backing-store
  namespace: openshift-storage
spec:
  s3Compatible:
    endpoint: https://rook-ceph-rgw-ocs-storagecluster-cephobjectstore.openshift-storage.svc:443
    secret:
      name: rook-ceph-object-user-ocs-storagecluster-cephobjectstore-noobaa-ceph-objectstore-user
      namespace: openshift-storage
    signatureVersion: v4
    targetBucket: nb.1683297491248.apps.orchidee.okd-dev.abes.fr
  type: s3-compatible
EOF
```

Le MCG s\'appuie sur la `storageClass` `openshift-storage.noobaa.io` qui
est définie à l\'installation de ODF.

``` bash
oc apply -f - <<EOF 
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: ceph-bucket
  namespace: default
spec:
  additionalConfig:
    bucketclass: nooba-default-bucket-class
  bucketName:
  generateBucketName: ceph-bucket
  storageClassName: openshift-storage.noobaa.io
EOF
```

La partie

``` bash
spec:
  additionalConfig:
    bucketclass: nooba-default-bucket-class
```

est optionnelle puisque `nooba-default-bucket-class` est la
`bucketClass` `spread` par défaut.

Si on veut utiliser le mode `mirror`, il faut ajouter une `bucketClass`
préalablement définie qui elle-même fait appel à différents
`backingStore`.

Pour renseigner un mode (Spread ou Mirror), il faut rajouter

``` bash
 oc get bucketclasses.noobaa.io  -n openshift-storage noobaa-default-bucket-class -o json | jq '.spec.placementPolicy.tiers[]+={"placement": "Spread"}'
```

### Exemple de création de `ObjectBucketClaim` MCG avec `noobaa`

#### Configuration par défaut de MCG

![mirrored](/files/selection_422.png)

#### Commandes noobaa

-   Création de l\'objet, avec la `bucketClass` par défaut
    `noobaa-default-bucket-class`, qui est liée au backingStore par
    défaut `noobaa-default-backing-store`, qui pointe lui-même vers le
    RGW installé par défaut par ODF.

``` bash
noobaa obc create tutu -n openshift-storage
noobaa obc status tutu -n openshift-storage
```

-   On récupère les accès précédemment créés et donnés par
    `noobaa obc status`

``` bash
noobaa backingstore create s3-compatible tutu --access-key="" --secret-key="" --target-bucket tutu-e50058f9-a891-43a0-b20a-3d757f80d941 -n openshift-storage
```

-   On peut créer des `bucketClass` en combinant différents
    `backingstore`

``` bash
noobaa bucketclass create placement-bucketclass tutu-bucket-class --placement=Mirror --backingstores=nat,noobaa-default-backing-store,test -n openshift-storage
```

-   On peut maintenant créer des buckets plus complexes à partir de ces
    nouvelles bucketclass

``` bash
noobaa obc create  mirrored-bucket --bucketclass=tutu-bucket-class
```

### Conclusion de la comparaison RGW/MCG

-   Pour les cas les plus simples, on peut aussi bien utiliser sans trop
    d\'effort la passerelle RADOS `RGW` que `MCG` sans placement pour
    rapidement créer des `obc`. Au final, les deux sont équivalents dans
    la mesure où ils pointent au final vers le même `endpoint` rook et
    le même bucket, c\'est à dire ceux créés par ODF à son installation.

-   MCG devient la seule solution à envisager pour des cas plus complexe
    de `mirror` ou de `spread`, ou de la combinaison des deux, si on
    travaille dans un environnement multicloud.

### Attaching OBC to a deployment

<https://blog.oddbit.com/post/2021-02-10-object-storage-with-openshift/>

Tout comme un `pvc`, il est possible d\'attacher un `obc` à un
deployment de façon à ce que le pod puisse lire les informations
relatives à l\'OBC.

Mais alors qu\'un pvc créé avec une storageClass `cephfs` ou `cephrbd`
va permettre à ce qu\'un pod accède aux informations contenues par le
moyen d\'un montage fs ou bloc, l\'obc a la particularité de monter deux
éléments contenant des variables, et que l\'application du pod va
pouvoir utiliser indirectement pour consommer les ressources de la
bucket.

#### secret

``` bash
oc extract secrets/ceph-bucket -n default --to=-
# AWS_ACCESS_KEY_ID
""
# AWS_SECRET_ACCESS_KEY
""
```

#### configMap

``` bash
oc get cm -n movies-docker-ceph movies-docker-ceph -oyaml | oc neat
apiVersion: v1
data:
  BUCKET_HOST: rook-ceph-rgw-ocs-storagecluster-cephobjectstore.openshift-storage.svc
  BUCKET_NAME: movies-docker-ceph-722ee512-df61-4d19-a8b9-efffa669abf7
  BUCKET_PORT: "443"
  BUCKET_REGION: ""
  BUCKET_SUBREGION: ""
kind: ConfigMap
metadata:
  labels:
    bucket-provisioner: openshift-storage.ceph.rook.io-bucket
  name: movies-docker-ceph
  namespace: movies-docker-ceph
```

#### Accès aux données de la bucket depuis un pod

Grâce à la directive `envFrom`

``` bash
apiVersion: v1
kind: Pod
metadata:
  name: bucket-example
spec:
  containers:
    - image: myimage
      env:
        - name: AWS_CA_BUNDLE
          value: /run/secrets/kubernetes.io/serviceaccount/service-ca.crt
      envFrom:
        - configMapRef:
            name: example-rgw
        - secretRef:
            name: example-rgw
      [...]
```
