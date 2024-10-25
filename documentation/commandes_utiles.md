# OKD et les commandes utiles

# OKD - L'indispensable

## Introduction

Les points abordés dans ce document porteront sur la connexion à un
cluster OKD et ses commandes utiles.

## Connexion aux clusters OKD

Afin de pouvoir se connecter aux clusters OKD, nous devons passer par
chopine qui est la machine à partir de laquelle les clusters ont étés
installés.

``` bash
2023/03/07 09:23:30: root@chopine:/root
> ll
drwxr-xr-x.  3 root    root         4096 Mar  1 15:52 orchidee-dev-v1212
drwxr-xr-x.  3 root    root           48 Mar  2 16:24 orchidee-test
```

Les installations des clusters OKD ont étés faites dans le répertoire
"/root" comme on peut l'aperçevoir sur block de code ci-dessus.

**Correction : Les installations été déplacées dans le répertoire
/data/root**

Afin de s'y connecter, nous devons exporter par variabale
d'environnement le fichier de configuration kubeconfig du cluster auquel
on veut se connecter. Ce fichier est pourvu d'un certificat qui est
utilisé pour l'authetification aux clusters par le biais de l'api.

> Le client oc de okd (correspond à kubelet sous kubernetes) est
> indispensable à l'authentification aux clusters.

``` bash
2023/03/07 09:36:43: root@chopine:/root/orchidee-dev-v1212/okd_install/auth
> ll
total 732
drwxr-x---. 2 root root     73 Feb 27 15:36 .
drwxr-xr-x. 4 root root   4096 Feb 23 15:54 ..
-rw-r-----. 1 root root     23 Feb 23 15:23 kubeadmin-password
-rw-------. 1 root root  24872 Mar  1 17:04 kubeconfig
-rw-r--r--. 1 root root 709759 Feb 23 16:31 oc_bash_completion
```

Pour obtenir ce fichier, il suffit de suivre le chemin suivant et de se
rendre dans le répertoire "auth".

Ensuite, on a plus qu'a exporter le fichier kubeconfig dans la variable
d'environnement KUBECONFIG qui sera utile à notre client okd (binaire :
oc).

``` bash
2023/03/07 09:41:43: root@chopine:/root/orchidee-dev-v1212/okd_install/auth
> export KUBECONFIG=/root/orchidee-dev-v1212/okd_install/auth/kubeconfig
```

On procède à la vérification de l'accessibilité de notre cluster comme
suit :

``` bash
2023/03/07 09:44:34: root@chopine:/root/orchidee-dev-v1212/okd_install/auth
> oc get nodes
NAME                          STATUS   ROLES                  AGE   VERSION
orchidee-ccbm8-master-0       Ready    control-plane,master   11d   v1.25.4+a34b9e9
orchidee-ccbm8-master-1       Ready    control-plane,master   11d   v1.25.4+a34b9e9
orchidee-ccbm8-master-2       Ready    control-plane,master   11d   v1.25.4+a34b9e9
orchidee-ccbm8-worker-9pg8j   Ready    worker                 11d   v1.25.4+a34b9e9
orchidee-ccbm8-worker-v55b4   Ready    worker                 11d   v1.25.4+a34b9e9
orchidee-ccbm8-worker-zhgql   Ready    worker                 11d   v1.25.4+a34b9e9
```

## Commandes

``` bash
> oc get nodes -o wide
NAME                          STATUS   ROLES                  AGE   VERSION           INTERNAL-IP     EXTERNAL-IP   OS-IMAGE                        KERNEL-VERSION           CONTAINER-RUNTIME
orchidee-ccbm8-master-0       Ready    control-plane,master   11d   v1.25.4+a34b9e9   10.35.212.53    <none>        Fedora CoreOS 37.20230110.3.1   6.0.18-300.fc37.x86_64   cri-o://1.25.1
orchidee-ccbm8-master-1       Ready    control-plane,master   11d   v1.25.4+a34b9e9   10.35.212.52    <none>        Fedora CoreOS 37.20230110.3.1   6.0.18-300.fc37.x86_64   cri-o://1.25.1
orchidee-ccbm8-master-2       Ready    control-plane,master   11d   v1.25.4+a34b9e9   10.35.212.153   <none>        Fedora CoreOS 37.20230110.3.1   6.0.18-300.fc37.x86_64   cri-o://1.25.1
orchidee-ccbm8-worker-9pg8j   Ready    worker                 11d   v1.25.4+a34b9e9   10.35.212.55    <none>        Fedora CoreOS 37.20230110.3.1   6.0.18-300.fc37.x86_64   cri-o://1.25.1
orchidee-ccbm8-worker-v55b4   Ready    worker                 11d   v1.25.4+a34b9e9   10.35.212.56    <none>        Fedora CoreOS 37.20230110.3.1   6.0.18-300.fc37.x86_64   cri-o://1.25.1
orchidee-ccbm8-worker-zhgql   Ready    worker                 11d   v1.25.4+a34b9e9   10.35.212.57    <none>        Fedora CoreOS 37.20230110.3.1   6.0.18-300.fc37.x86_64   cri-o://1.25.1
```

Obtenir les noeuds d'un cluster et tout un éventail d'information.

``` bash
> oc get nodes
NAME                          STATUS   ROLES                  AGE   VERSION
orchidee-ccbm8-master-0       Ready    control-plane,master   11d   v1.25.4+a34b9e9
orchidee-ccbm8-master-1       Ready    control-plane,master   11d   v1.25.4+a34b9e9
orchidee-ccbm8-master-2       Ready    control-plane,master   11d   v1.25.4+a34b9e9
orchidee-ccbm8-worker-9pg8j   Ready    worker                 11d   v1.25.4+a34b9e9
orchidee-ccbm8-worker-v55b4   Ready    worker                 11d   v1.25.4+a34b9e9
orchidee-ccbm8-worker-zhgql   Ready    worker                 11d   v1.25.4+a34b9e9
```

Sans le -o wide, la sortie est un peu plus pauvre.

``` bash
> oc get pods -A -o wide
NAMESPACE                                          NAME                                                              READY   STATUS      RESTARTS       AGE     IP              NODE                          NOMINATED NODE   READINESS GATES
awx                                                awx-c467cf964-k8phg                                               4/4     Running     0              5d16h   10.129.2.53     orchidee-ccbm8-worker-zhgql   <none>           <none>
awx                                                awx-operator-controller-manager-56f98985c8-mmksz                  2/2     Running     0              5d16h   10.129.2.52     orchidee-ccbm8-worker-zhgql   <none>           <none>
awx                                                awx-postgres-13-0                                                 1/1     Running     0              5d16h   10.131.0.116    orchidee-ccbm8-worker-9pg8j   <none>           <none>
awx2                                               awx-c467cf964-vgqk9                                               4/4     Running     0              6d13h   10.128.2.38     orchidee-ccbm8-worker-v55b4   <none>           <none>
awx2                                               awx-operator-controller-manager-56f98985c8-hbxz5                  2/2     Running     0              6d14h   10.128.2.36     orchidee-ccbm8-worker-v55b4   <none>           <none>
awx2                                               awx-postgres-13-0                                                 1/1     Running     0              6d14h   10.128.2.37     orchidee-ccbm8-worker-v55b4   <none>           <none>
awx3                                               awx-c467cf964-jm44p                                               4/4     Running     0              5d17h   10.129.2.51     orchidee-ccbm8-worker-zhgql   <none>           <none>
awx3                                               awx-operator-controller-manager-56f98985c8-hvf7r                  2/2     Running     0              5d17h   10.129.2.50     orchidee-ccbm8-worker-zhgql   <none>           <none>
awx3                                               awx-postgres-13-0                                                 1/1     Running     0              5d17h   10.131.0.111    orchidee-ccbm8-worker-9pg8j   <none>           <none>
openshift-apiserver-operator                       openshift-apiserver-operator-6d5d696655-jq8cm                     1/1     Running     2 (11d ago)    11d     10.130.0.15     orchidee-ccbm8-master-1       <none>           <none>
openshift-apiserver                                apiserver-859d577579-5fj29                                        2/2     Running     0              11d     10.129.0.28     orchidee-ccbm8-master-2       <none>           <none>
openshift-apiserver                                apiserver-859d577579-j7952                                        2/2     Running     0              11d     10.130.0.44     orchidee-ccbm8-master-1       <none>           <none>
openshift-apiserver                                apiserver-859d577579-t8kcn                                        2/2     Running     0              11d     10.128.0.17     orchidee-ccbm8-master-0       <none>           <none>
openshift-authentication-operator                  authentication-operator-68c75f854d-rqp2x                          1/1     Running     2 (11d ago)    11d     10.130.0.28     orchidee-ccbm8-master-1       <none>           <none>
openshift-authentication                           oauth-openshift-867cc47559-2vdfp                                  1/1     Running     0              11d     10.130.0.47     orchidee-ccbm8-master-1       <none>           <none>
openshift-authentication                           oauth-openshift-867cc47559-5pkbd                                  1/1     Running     0              11d     10.129.0.35     orchidee-ccbm8-master-2       <none>           <none>
openshift-authentication                           oauth-openshift-867cc47559-hmf94                                  1/1     Running     0              11d     10.128.0.31     orchidee-ccbm8-master-0       <none>           <none>
openshift-cloud-controller-manager-operator        cluster-cloud-controller-manager-operator-8d876c5cd-98h85         2/2     Running     2 (11d ago)    11d     10.35.212.52    orchidee-ccbm8-master-1       <none>           <none>
openshift-cloud-credential-operator                cloud-credential-operator-5c588fc678-mnvhg                        2/2     Running     0              11d     10.130.0.20     orchidee-ccbm8-master-1       <none>           <none>
openshift-cluster-csi-drivers                      ovirt-csi-driver-controller-7548ffcb77-hnt9p                      7/7     Running     6 (3d9h ago)   11d     10.35.212.153   orchidee-ccbm8-master-2       <none>           <none>
openshift-cluster-csi-drivers                      ovirt-csi-driver-controller-7548ffcb77-vc8zp                      7/7     Running     3 (3d9h ago)   11d     10.35.212.52    orchidee-ccbm8-master-1       <none>           <none>
openshift-cluster-csi-drivers                      ovirt-csi-driver-node-g89k6                                       3/3     Running     3 (3d9h ago)   11d     10.35.212.57    orchidee-ccbm8-worker-zhgql   <none>           <none>
openshift-cluster-csi-drivers                      ovirt-csi-driver-node-jj98q                                       3/3     Running     2 (3d9h ago)   11d     10.35.212.52    orchidee-ccbm8-master-1       <none>           <none>
openshift-cluster-csi-drivers                      ovirt-csi-driver-node-tp7gq                                       3/3     Running     4 (3d9h ago)   11d     10.35.212.56    orchidee-ccbm8-worker-v55b4   <none>           <none>
openshift-cluster-csi-drivers                      ovirt-csi-driver-node-xrgfd                                       3/3     Running     3 (3d9h ago)   11d     10.35.212.55    orchidee-ccbm8-worker-9pg8j   <none>           <none>
openshift-cluster-csi-drivers                      ovirt-csi-driver-node-zglsb                                       3/3     Running     2 (3d9h ago)   11d     10.35.212.53    orchidee-ccbm8-master-0       <none>           <none>
openshift-cluster-csi-drivers                      ovirt-csi-driver-node-zl2r9                                       3/3     Running     2 (3d9h ago)   11d     10.35.212.153   orchidee-ccbm8-master-2       <none>           <none>
openshift-cluster-csi-drivers                      ovirt-csi-driver-operator-757955c497-cgprt                        1/1     Running     4 (11d ago)    11d     10.129.0.10     orchidee-ccbm8-master-2       <none>           <none>
openshift-cluster-machine-approver                 machine-approver-59d8d57687-xlfph                                 2/2     Running     3 (11d ago)    11d     10.35.212.52    orchidee-ccbm8-master-1       <none>           <none>
openshift-cluster-node-tuning-operator             cluster-node-tuning-operator-7557b68c99-g5fwv                     1/1     Running     1 (11d ago)    11d     10.130.0.11     orchidee-ccbm8-master-1       <none>           <none>
openshift-cluster-node-tuning-operator             tuned-98x28                                                       1/1     Running     0              11d     10.35.212.52    orchidee-ccbm8-master-1       <none>           <none>
openshift-cluster-node-tuning-operator             tuned-ctcxl                                                       1/1     Running     0              11d     10.35.212.57    orchidee-ccbm8-worker-zhgql   <none>           <none>
openshift-cluster-node-tuning-operator             tuned-f8jzc                                                       1/1     Running     0              11d     10.35.212.53    orchidee-ccbm8-master-0       <none>           <none>
openshift-cluster-node-tuning-operator             tuned-lk476                                                       1/1     Running     0              11d     10.35.212.55    orchidee-ccbm8-worker-9pg8j   <none>           <none>
openshift-cluster-node-tuning-operator             tuned-lpclj                                                       1/1     Running     0              11d     10.35.212.153   orchidee-ccbm8-m
...
```

Avoir tous les pods tournant dans le cluster de tous les namespaces
(-A).

> Si l'on ne spécifie pas le -A, il affichera par défaut les pods du
> namespace "default".

Les adresses que l'on voit pour chacun de ses pods nous permettent de
juger leur degré d'exposition. (Réseau des noeuds ou réseau des pods)

``` bash
> oc get
Display all 196 possibilities? (y or n)
alertmanagerconfigs.monitoring.coreos.com                        kubecontrollermanagers.operator.openshift.io
alertmanagers.monitoring.coreos.com                              kubeletconfigs.machineconfiguration.openshift.io
apirequestcounts.apiserver.openshift.io                          kubeschedulers.operator.openshift.io
apiservers.config.openshift.io                                   kubestorageversionmigrators.operator.openshift.io
apiservices.apiregistration.k8s.io                               leases.coordination.k8s.io
appliedclusterresourcequotas.quota.openshift.io                  limitranges
authentications.config.openshift.io                              localvolumediscoveries.local.storage.openshift.io
authentications.operator.openshift.io                            localvolumediscoveryresults.local.storage.openshift.io
awxbackups.awx.ansible.com                                       localvolumesets.local.storage.openshift.io
awxrestores.awx.ansible.com                                      localvolumes.local.storage.openshift.io
awxs.awx.ansible.com                                             machineautoscalers.autoscaling.openshift.io
baremetalhosts.metal3.io                                         machineconfigpools.machineconfiguration.openshift.io
bmceventsubscriptions.metal3.io                                  machineconfigs.machineconfiguration.openshift.io
brokertemplateinstances.template.openshift.io                    machinehealthchecks.machine.openshift.io
buildconfigs.build.openshift.io                                  machinesets.machine.openshift.io
builds.build.openshift.io                                        machines.machine.openshift.io
builds.config.openshift.io                                       mutatingwebhookconfigurations.admissionregistration.k8s.io
catalogsources.operators.coreos.com                              namespaces
certificatesigningrequests.certificates.k8s.io                   network-attachment-definitions.k8s.cni.cncf.io
cloudcredentials.operator.openshift.io                           networkpolicies.networking.k8s.io
clusterautoscalers.autoscaling.openshift.io                      networks.config.openshift.io
clustercsidrivers.operator.openshift.io                          networks.operator.openshift.io
clusteroperators.config.openshift.io                             nodes
```

En sachant que l'autocomplétion a été mise en place sur chopine, vous
pouvez avoir le listing des ressources d'un namespace donné en tapant
"oc get" suivi d'une tabulation (Pas besoin de connaître les commande
sur le bout des doigts) puis all.

``` bash
> oc get all -n awx -o wide
NAME                                                   READY   STATUS    RESTARTS   AGE     IP             NODE                          NOMINATED NODE   READINESS GATES
pod/awx-c467cf964-k8phg                                4/4     Running   0          5d17h   10.129.2.53    orchidee-ccbm8-worker-zhgql   <none>           <none>
pod/awx-operator-controller-manager-56f98985c8-mmksz   2/2     Running   0          5d17h   10.129.2.52    orchidee-ccbm8-worker-zhgql   <none>           <none>
pod/awx-postgres-13-0                                  1/1     Running   0          5d17h   10.131.0.116   orchidee-ccbm8-worker-9pg8j   <none>           <none>

NAME                                                      TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)    AGE     SELECTOR
service/awx-operator-controller-manager-metrics-service   ClusterIP   172.30.159.168   <none>        8443/TCP   5d17h   control-plane=controller-manager,helm.sh/chart=awx-operator
service/awx-postgres-13                                   ClusterIP   None             <none>        5432/TCP   5d17h   app.kubernetes.io/component=database,app.kubernetes.io/instance=postgres-13-awx,app.kubernetes.io/managed-by=awx-operator,app.kubernetes.io/name=postgres-13,app.kubernetes.io/part-of=awx
service/awx-service                                       ClusterIP   172.30.92.222    <none>        80/TCP     5d17h   app.kubernetes.io/component=awx,app.kubernetes.io/managed-by=awx-operator,app.kubernetes.io/name=awx

NAME                                              READY   UP-TO-DATE   AVAILABLE   AGE     CONTAINERS                      IMAGES                                                                                                    SELECTOR
deployment.apps/awx                               1/1     1            1           5d17h   redis,awx-web,awx-task,awx-ee   docker.io/redis:7,quay.io/ansible/awx:21.12.0,quay.io/ansible/awx:21.12.0,quay.io/ansible/awx-ee:latest   app.kubernetes.io/component=awx,app.kubernetes.io/managed-by=awx-operator,app.kubernetes.io/name=awx
deployment.apps/awx-operator-controller-manager   1/1     1            1           5d17h   kube-rbac-proxy,awx-manager     gcr.io/kubebuilder/kube-rbac-proxy:v0.13.0,quay.io/ansible/awx-operator:1.2.0                             control-plane=controller-manager,helm.sh/chart=awx-operator

NAME                                                         DESIRED   CURRENT   READY   AGE     CONTAINERS                      IMAGES                                                                                                    SELECTOR
replicaset.apps/awx-c467cf964                                1         1         1       5d17h   redis,awx-web,awx-task,awx-ee   docker.io/redis:7,quay.io/ansible/awx:21.12.0,quay.io/ansible/awx:21.12.0,quay.io/ansible/awx-ee:latest   app.kubernetes.io/component=awx,app.kubernetes.io/managed-by=awx-operator,app.kubernetes.io/name=awx,pod-template-hash=c467cf964
replicaset.apps/awx-operator-controller-manager-56f98985c8   1         1         1       5d17h   kube-rbac-proxy,awx-manager     gcr.io/kubebuilder/kube-rbac-proxy:v0.13.0,quay.io/ansible/awx-operator:1.2.0                             control-plane=controller-manager,helm.sh/chart=awx-operator,pod-template-hash=56f98985c8

NAME                               READY   AGE     CONTAINERS   IMAGES
statefulset.apps/awx-postgres-13   1/1     5d17h   postgres     postgres:13

NAME                           HOST/PORT                               PATH   SERVICES      PORT   TERMINATION     WILDCARD
route.route.openshift.io/awx   awx-awx.apps.orchidee.okd-dev.abes.fr          awx-service   http   edge/Redirect   None
```

L'argument all suivit du namespace nous permet de connaître toutes les
ressources créées dans le namespace (-n : namespace).

``` bash
> oc get -n awx deployment awx -o yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    deployment.kubernetes.io/revision: "1"
    kubectl.kubernetes.io/last-applied-configuration: '{"apiVersion":"apps/v1","kind":"Deployment","metadata":{"labels":{"app.kubernetes.io/component":"awx","app.kubernetes.io/managed-by":"awx-operator","app.kubernetes.io/name":"awx","app.kubernetes.io/operator-version":"1.2.0","app.kubernetes.io/part-of":"awx","app.kubernetes.io/version":"21.12.0"},"name":"awx","namespace":"awx"},"spec":{"replicas":1,"selector":{"matchLabels":{"app.kubernetes.io/component":"awx","app.kubernetes.io/managed-by":"awx-operator","app.kubernetes.io/name":"awx"}},"template":{"metadata":{"labels":{"app.kubernetes.io/component":"awx","app.kubernetes.io/managed-by":"awx-operator","app.kubernetes.io/name":"awx","app.kubernetes.io/operator-version":"1.2.0","app.kubernetes.io/part-of":"awx","app.kubernetes.io/version":"21.12.0"}},"spec":{"containers":[{"args":["redis-server","/etc/redis.conf"],"image":"docker.io/redis:7","imagePullPolicy":"IfNotPresent","name":"redis","resources":{"requests":{"cpu":"50m","memory":"64Mi"}},"volumeMounts":[{"mountPath":"/etc/redis.conf","name":"awx-redis-config","readOnly":true,"subPath":"redis.conf"},{"mountPath":"/var/run/redis","name":"awx-redis-socket"},{"mountPath":"/data","name":"awx-redis-data"}]},{"args":["/usr/bin/launch_awx.sh"],"env":[{"name":"MY_POD_NAMESPACE","valueFrom":{"fieldRef":{"fieldPath":"metadata.namespace"}}},{"name":"UWSGI_MOUNT_PATH","value":"/"}],"image":"quay.io/ansible/awx:21.12.0","imagePullPolicy":"IfNotPresent","name":"awx-web","ports":[{"containerPort":8052}],"resources":{"requests":{"cpu":"100m","memory":"128Mi"}},"volumeMounts":[{"mountPath":"/etc/tower/conf.d/execution_environments.py","name":"awx-application-credentials","readOnly":true,"subPath":"execution_environments.py"},{"mountPath":"/etc/tower/conf.d/credentials.py","name":"awx-application-credentials","readOnly":true,"subPath":"credentials.py"}
...
```

On extrait la description de la ressource de déploiement sous forme yaml
du deploiement awx dans le namespace awx. Autrement dit, c'est un
manifest qui implémente la ressource déploiement par laquelle on peut
créer des pods/containers et spécifier le stockage des données et bien
d'autres fonctionnalités.

> À savoir que l'on peut faire de même pour les pods, routes, services,
> ...

``` bash
> oc describe pods -n awx awx-c467cf964-k8phg
Name:         awx-c467cf964-k8phg
Namespace:    awx
Priority:     0
Node:         orchidee-ccbm8-worker-zhgql/10.35.212.57
Start Time:   Wed, 01 Mar 2023 16:59:10 +0100
Labels:       app.kubernetes.io/component=awx
              app.kubernetes.io/managed-by=awx-operator
              app.kubernetes.io/name=awx
              app.kubernetes.io/operator-version=1.2.0
              app.kubernetes.io/part-of=awx
              app.kubernetes.io/version=21.12.0
              pod-template-hash=c467cf964
Annotations:  k8s.ovn.org/pod-networks:
                {"default":{"ip_addresses":["10.129.2.53/23"],"mac_address":"0a:58:0a:81:02:35","gateway_ips":["10.129.2.1"],"ip_address":"10.129.2.53/23"...
              k8s.v1.cni.cncf.io/network-status:
                [{
                    "name": "ovn-kubernetes",
                    "interface": "eth0",
                    "ips": [
                        "10.129.2.53"
                    ],
                    "mac": "0a:58:0a:81:02:35",
                    "default": true,
                    "dns": {}
                }]
              k8s.v1.cni.cncf.io/networks-status:
                [{
                    "name": "ovn-kubernetes",
                    "interface": "eth0",
                    "ips": [
                        "10.129.2.53"
                    ],
                    "mac": "0a:58:0a:81:02:35",
                    "default": true,
                    "dns": {}
                }]
              openshift.io/scc: privileged
Status:       Running
IP:           10.129.2.53
IPs:
  IP:           10.129.2.53
Controlled By:  ReplicaSet/awx-c467cf964
Init Containers:
  init:
    Container ID:  cri-o://fd955213a2f674ca5225bf0e23ac6a60ad071979fcf76205eb2d4ed8fc51036b
    Image:         quay.io/ansible/awx-ee:latest
    Image ID:      quay.io/ansible/awx-ee@sha256:73f3d4ec9b79f40710d4c332b64b8becd7b8a5e7c8676cacfb96affba57663b0
    Port:          <none>
    Host Port:     <none>
    Command:
      /bin/sh
      -c
      hostname=$MY_POD_NAME
      receptor --cert-makereq bits=2048 commonname=$hostname dnsname=$hostname nodeid=$hostname outreq=/etc/receptor/tls/receptor.req outkey=/etc/receptor/tls/receptor.key
      receptor --cert-signreq req=/etc/receptor/tls/receptor.req cacert=/etc/receptor/tls/ca/receptor-ca.crt cakey=/etc/receptor/tls/ca/receptor-ca.key outcert=/etc/receptor/tls/receptor.crt verify=yes

    State:          Terminated
      Reason:       Completed
      Exit Code:    0
      Started:      Wed, 01 Mar 2023 16:59:11 +0100
      Finished:     Wed, 01 Mar 2023 16:59:12 +0100
    Ready:          True
    Restart Count:  0
    Requests:
      cpu:     100m
      memory:  128Mi
    Environment:
      MY_POD_NAME:  awx-c467cf964-k8phg (v1:metadata.name)
    Mounts:
      /etc/receptor/tls/ from awx-receptor-tls (rw)
      /etc/receptor/tls/ca/receptor-ca.crt from awx-receptor-ca (ro,path="tls.crt")
      /etc/receptor/tls/ca/receptor-ca.key from awx-receptor-ca (ro,path="tls.key")
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-5l4td (ro)
Containers:
  redis:
    Container ID:  cri-o://abc54a5550dd582419c8be2af151bf1570f728e40bec1a863e691143a08a412a
    Image:         docker.io/redis:7
    Image ID:      docker.io/library/redis@sha256:6a59f1cbb8d28ac484176d52c473494859a512ddba3ea62a547258cf16c9b3ae
    Port:          <none>
    Host Port:     <none>
    Args:
      redis-server
      /etc/redis.conf
    State:          Running
      Started:      Wed, 01 Mar 2023 16:59:13 +0100
    Ready:          True
    Restart Count:  0
    Requests:
      cpu:        50m
      memory:     64Mi
    Environment:  <none>
    Mounts:
      /data from awx-redis-data (rw)
      /etc/redis.conf from awx-redis-config (ro,path="redis.conf")
      /var/run/redis from awx-redis-socket (rw)
      /var/run/secrets/kubernetes.io/serviceaccount from kube-api-access-5l4td (ro)
```

Describe est un outil qui peut s'avérer intéressant pour débuguer, on
aura toutes les informations concernant le pod et ses events. Si ce pod
plante, on pourra avoir des informations complémentaires dans l'encart
"event", qui indiquera si le pod est redémarré ou alors recréé (mode
liveness et readiness).

> La description d'état peut se faire sur n'importe quelle ressource.

``` bash
> oc logs --tail=20 -n awx awx-operator-controller-manager-56f98985c8-mmksz
-------------------------------------------------------------------------------
{"level":"info","ts":1677686543.7269216,"logger":"proxy","msg":"Read object from cache","resource":{"IsResourceRequest":true,"Path":"/api/v1/namespaces/awx/secrets/awx-receptor-work-signing","Verb":"get","APIPrefix":"api","APIGroup":"","APIVersion":"v1","Namespace":"awx","Resource":"secrets","Subresource":"","Name":"awx-receptor-work-signing","Parts":["secrets","awx-receptor-work-signing"]}}

--------------------------- Ansible Task StdOut -------------------------------

 TASK [Remove ownerReferences reference] ********************************
ok: [localhost] => (item=None) => {"censored": "the output has been hidden due to the fact that 'no_log: true' was specified for this result", "changed": false}

-------------------------------------------------------------------------------
{"level":"info","ts":1677686544.3118424,"logger":"runner","msg":"Ansible-runner exited successfully","job":"221828814128904738","name":"awx","namespace":"awx"}

----- Ansible Task Status Event StdOut (awx.ansible.com/v1beta1, Kind=AWX, awx/awx) -----


PLAY RECAP *********************************************************************
localhost                  : ok=77   changed=0    unreachable=0    failed=0    skipped=71   rescued=0    ignored=1


----------
{"level":"info","ts":1677686544.3551552,"logger":"KubeAPIWarningLogger","msg":"unknown field \"status.conditions[1].ansibleResult\""}
```

On peut se procurer les logs d'un pod dans un namespace donné de la
manière présentée ci-dessus (l'option -f est possible pour le realtime).

Utile pour débuguer le déploiement d'une app par un opérateur (en
l'occurence awx) et pour tout autre cas.

> Si le namespace n'est pas précisé, il va attaquer celui par défaut

TODO :

-   create
-   apply
-   replace
-   delete
