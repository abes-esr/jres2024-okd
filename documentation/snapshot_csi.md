# Snapshots CSI

### Prérequis

[Drivers CSI](drivers_csi.md)

### Introduction

Seuls certains drivers ont la possibilité de d\'effectuer des snapshots
de volumes. Ce n\'est pas le cas du driver `ovirt-csi` par défaut, mais
par contre ces drivers supportent cette fonction:

``` bash
oc get volumesnapshotclasses.snapshot.storage.k8s.io 
NAME                                        DRIVER                                  DELETIONPOLICY   AGE
csi-nfs-snapclass                           nfs.csi.k8s.io                          Delete           22m
ocs-storagecluster-cephfsplugin-snapclass   openshift-storage.cephfs.csi.ceph.com   Delete           374d
ocs-storagecluster-rbdplugin-snapclass      openshift-storage.rbd.csi.ceph.com      Delete           374d
```

## Mise en oeuvre avec nfs.csi.k8s.io

<https://github.com/kubernetes-csi/csi-driver-nfs/tree/master/deploy/example/snapshot>

La logique rejoint celle employée par les `storageClass` et les `pv`.

Il faut donc d\'abord définir un `volumeSnapshotClass`

``` bash
oc apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-nfs-snapclass
driver: nfs.csi.k8s.io
deletionPolicy: Delete
EOF
```

Puis on définit un pvc qui crée un `volumeSnapshot`

``` bash
oc apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: test-nfs-snapshot
spec:
  volumeSnapshotClassName: csi-nfs-snapclass
  source:
    persistentVolumeClaimName: movies-wikibase-mysql-claim6
EOF
```

On vérifie que le snapshot s\'est bien effectué:

``` bash
oc get vsc
NAME                                               READYTOUSE   RESTORESIZE   DELETIONPOLICY   DRIVER           VOLUMESNAPSHOTCLASS   VOLUMESNAPSHOT      VOLUMESNAPSHOTNAMESPACE   AGE
snapcontent-f0f75a60-c647-4a68-96d7-9af2a0f0882f   true         33989110      Delete           nfs.csi.k8s.io   csi-nfs-snapclass     test-nfs-snapshot   movies-docker-ceph        20h
```

``` bash
oc get vs
NAME                READYTOUSE   SOURCEPVC                      SOURCESNAPSHOTCONTENT   RESTORESIZE   SNAPSHOTCLASS       SNAPSHOTCONTENT                                    CREATIONTIME   AGE
test-nfs-snapshot   true         movies-wikibase-mysql-claim6                           33989110      csi-nfs-snapclass   snapcontent-f0f75a60-c647-4a68-96d7-9af2a0f0882f   20h            20h
```

``` bash
oc describe volumesnapshot test-nfs-snapshot
Name:         test-nfs-snapshot
Namespace:    movies-docker-ceph
Labels:       <none>
Annotations:  <none>
API Version:  snapshot.storage.k8s.io/v1
Kind:         VolumeSnapshot
Metadata:
  Creation Timestamp:  2024-05-13T17:44:34Z
  Finalizers:
    snapshot.storage.kubernetes.io/volumesnapshot-as-source-protection
    snapshot.storage.kubernetes.io/volumesnapshot-bound-protection
  Generation:  1
  Managed Fields:
    API Version:  snapshot.storage.k8s.io/v1
    Fields Type:  FieldsV1
    fieldsV1:
      f:metadata:
        f:annotations:
          .:
          f:kubectl.kubernetes.io/last-applied-configuration:
      f:spec:
        .:
        f:source:
          .:
          f:persistentVolumeClaimName:
        f:volumeSnapshotClassName:
    Manager:      kubectl-client-side-apply
    Operation:    Update
    Time:         2024-05-13T17:44:34Z
    API Version:  snapshot.storage.k8s.io/v1
    Fields Type:  FieldsV1
    fieldsV1:
      f:metadata:
        f:finalizers:
          .:
          v:"snapshot.storage.kubernetes.io/volumesnapshot-as-source-protection":
          v:"snapshot.storage.kubernetes.io/volumesnapshot-bound-protection":
    Manager:      snapshot-controller
    Operation:    Update
    Time:         2024-05-13T17:44:34Z
    API Version:  snapshot.storage.k8s.io/v1
    Fields Type:  FieldsV1
    fieldsV1:
      f:status:
        .:
        f:boundVolumeSnapshotContentName:
        f:creationTime:
        f:readyToUse:
        f:restoreSize:
    Manager:         snapshot-controller
    Operation:       Update
    Subresource:     status
    Time:            2024-05-13T17:44:46Z
  Resource Version:  566490942
  UID:               f0f75a60-c647-4a68-96d7-9af2a0f0882f
Spec:
  Source:
    Persistent Volume Claim Name:  movies-wikibase-mysql-claim6
  Volume Snapshot Class Name:      csi-nfs-snapclass
Status:
  Bound Volume Snapshot Content Name:  snapcontent-f0f75a60-c647-4a68-96d7-9af2a0f0882f
  Creation Time:                       2024-05-13T17:44:46Z
  Ready To Use:                        true
  Restore Size:                        33989110
Events:
  Type    Reason            Age   From                 Message
  ----    ------            ----  ----                 -------
  Normal  CreatingSnapshot  68m   snapshot-controller  Waiting for a snapshot movies-docker-ceph/test-nfs-snapshot to be created by the CSI driver.
  Normal  SnapshotCreated   68m   snapshot-controller  Snapshot movies-docker-ceph/test-nfs-snapshot was successfully created by the CSI driver.
  Normal  SnapshotReady     68m   snapshot-controller  Snapshot movies-docker-ceph/test-nfs-snapshot is ready to use.
```

Le snapshot apparaît bien au niveau du filesystem du NAS:

``` bash
[root@methana pool_SAS_2]# ll OKD2/snapshot-f0f75a60-c647-4a68-96d7-9af2a0f0882f/pvc-48d777ae-dde9-4c27-85c6-4390a13b26fe.tar.gz  -h
-rw-r--r--. 1 nobody nobody 33M May 13 19:45 OKD2/snapshot-f0f75a60-c647-4a68-96d7-9af2a0f0882f/pvc-48d777ae-dde9-4c27-85c6-4390a13b26fe.tar.gz
```
