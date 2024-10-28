======= Lien NFS =======

## Drivers CSI

Les `persistentVolumes` ou `pv` permettent de définir des volumes gérés
nativement par OKD par le biais de storageClass. Il existe différentes
façons de définir une storageClass, La méthode moderne recommandée par
OKD est de passer des `Container Storage Interface`, autrement dit des
programmes qui exécutent l\'interfaçage entre Kubernetes et le provider
de stockage.
<https://docs.okd.io/4.13/storage/container_storage_interface/persistent-storage-csi.html>

Dans notre cas, le `sc` par défaut est `ovirt-csi`, qui a été
provisionné par l\'installateur `IPI`.
<https://docs.okd.io/4.13/storage/container_storage_interface/persistent-storage-csi-ovirt.html>.
Ce driver crée des disques ovirt rattachés aux VMs worker d\'OKD. Bien
que pratique dans notre cas, ce driver n\'est maintenant plus maintenu à
causes de ses limitations (et de la fin de maintenant de RHV). Ces
limitations sont entre autre:

-   pas de snapshot possible
-   pas de mode ReadWriteMany (RWX)

Il est donc impossible de créer des `persistentVolumesClaim` avec ce
driver. Plusieurs choix s\'offrent alors à nous suivant cette matrice
des CSI supportés:

![](/files/selection_393.png)

L\'idéal pour nous sera d\'utiliser OpenDataFoundation (`ODF`) avec le
support de CephFS, mais il est aussi possible d\'adopter un montage
classique NFS que nous décrirons ici

## Mise en pratique

### Création du partage sur le NAS

Nous allons potentiellement utiliser le partage sur 4 NAS:

-   methana
-   erebus
-   sotora
-   solo

et partager chacun des volumes de ces NAS.

``` bash
cat /etc/exports
/pool_SAS_1 10.35.0.0/16(rw,root_squash) 10.34.102.0/23(rw,root_squash)
/pool_SAS_2 10.35.0.0/16(rw,root_squash) 10.34.102.0/23(rw,root_squash)
/pool_SSD_1 10.35.0.0/16(rw,root_squash) 10.34.102.0/23(rw,root_squash)
```

``` bash
systemctl reload nfs-server
```

### Création de PV

La documentation de `oc` prévoit un partage NFS natif en ligne de
commande

``` bash
oc set volume --help
...
    -t, --type='':
    Type of the volume source for add operation. Supported options: emptyDir, hostPath, secret, configmap, persistentVolumeClaim
```

Mais son utilisation dans un deployment n\'est plus nativement
supportée.

Il faut donc passer par la méthode traditionnelle kubernetes qui est la
création d\'un PV:

``` bash
oc apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: methana-sas-1
spec:
  capacity:
    storage: 1Gi 
  accessModes:
  - ReadWriteMany
  nfs: 
    path: /pool_SAS_1
    server: methana.v102.abes.fr 
  persistentVolumeReclaimPolicy: Retain
EOF
```

``` bash
oc get pv
```

### Création de PVC

Une fois que ce `PV` est créé, il reste à définir un `PVC`, qui va
réserver pour un namespace donné un espace sur ce `PV`

``` bash
oc apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: shared
spec:
  accessModes:
    - ReadWriteMany 
  resources:
    requests:
      storage: 1Gi 
  volumeName: methana-sas-1
  storageClassName: ""
EOF
```

``` bash
oc get pvc
```

### Déclaration de ce PVC à un deployment

Il reste à attacher ce PVC à la définition d\'un deployment:

``` bash
oc set volume deploy/movies-wikibase --add --claim-name=shared --mount-path=/var/www/html --sub-path=movies_data/shared --read-only=true --overwrite
```

``` yaml
...
        volumeMounts:
        - mountPath: /var/www/html
          name: shared
          readOnly: true
          subPath: movies_data/shared
...
      volumes:
      - name: shared
        persistentVolumeClaim:
          claimName: shared
```

A noter qu\'on utilise la directive `subPath` pour accéder sur le NAS au
chemin nécessaire.

On vérifie:

``` console
oc rsh container bash
mount
methana.v102.abes.fr:/pool_SAS_2/movies_data/shared on /shared type nfs4 (ro,relatime,vers=4.2,rsize=1048576,wsize=1048576,namlen=255,hard,proto=tcp,timeo=600,retrans=2,sec=sys,clientaddr=10.35.212.57,local_lock=none,addr=10.34.103.43)
```

On cherche les pvc qui ont le nom `shared`

``` bash
oc get pod -o json | jq -r '.items[]|select(.spec.volumes[]|select(.persistentVolumeClaim.claimName|test("shared"))?).metadata.name
movies-wikibase-67f674949-957x2
movies-wikibase-jobrunner-5f9889b6c9-thslv
```

``` bash
oc get deploy -o json | jq -r '.items[]|select(.spec.template.spec.volumes[]?|select(.persistentVolumeClaim.claimName|test("shared"))?).metadata.name
movies-wikibase
movies-wikibase-jobrunner
```

### Détachement de PVC

On peut détacher ces volumes d\'un deployment avec la commande `oc`

``` bash
oc set volume deploy/movies-wikibase --remove --name=shared
```

Si on veut supprimer le pvc:

``` bash
oc delete pvc shared
```

Une fois que le pvc est supprimé, il se peut que, le `pv` reste en état
`released`, ce qui le rend pas réutilisable.

``` bash
oc get pv
methana-sas-1 1Gi RWX Retain Released  movies-docker/shared                                                      
```

Pour pouvoir le réutiliser, il faut libérer le bail du pvc:

``` bash
oc patch pv applis-qualimarc-prod -p '{"spec":{"claimRef": null}}'
```

## Divers

Lister les pvs qui sont RWX

``` bash
oc get pv -o json | jq -r '.items[]|select(.spec.accessModes[]?|test("Many")).metadata.name'
```

Lister les volumes en doublons:

``` bash
docker-compose config | yq -o json | jq -r '.services[].volumes[]?.source' |sort | uniq -d
```
