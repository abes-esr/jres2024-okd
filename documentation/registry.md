# Registry d\'images Docker

## Nécessité d\'un registry

Openshift/OKD, contrairement à une stack kubernetes standard, intègre un
registry d\'image prêt à l\'emploi déployé sous forme d\'opérateur:

``` /bash
oc get all -n openshift-image-registry
NAME                                                   READY   STATUS      RESTARTS      AGE
pod/cluster-image-registry-operator-7f69b9db5d-245nn   1/1     Running     1 (88d ago)   101d
pod/image-pruner-28644480-9nrk5                        0/1     Completed   0             2d16h
pod/image-pruner-28645920-x552f                        0/1     Completed   0             40h
pod/image-pruner-28647360-ctvsr                        0/1     Completed   0             16h
pod/image-registry-7476b49c58-dwfjd                    1/1     Running     0             3d3h
pod/node-ca-2b496                                      1/1     Running     7             419d
pod/node-ca-6nmpz                                      1/1     Running     8             419d
pod/node-ca-9mxdc                                      1/1     Running     10            419d
pod/node-ca-fcjrk                                      1/1     Running     7             419d
pod/node-ca-kmftk                                      1/1     Running     7             419d
pod/node-ca-lh2z9                                      1/1     Running     6             419d
pod/node-ca-q9skh                                      1/1     Running     8             419d
pod/node-ca-tm79n                                      1/1     Running     6             412d
pod/node-ca-wlgcf                                      1/1     Running     6             412d
pod/node-ca-xlcp8                                      1/1     Running     5             412d

NAME                              TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)     AGE
service/image-registry            ClusterIP   172.30.183.182   <none>        5000/TCP    483d
service/image-registry-operator   ClusterIP   None             <none>        60000/TCP   483d

NAME                     DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
daemonset.apps/node-ca   10        10        10      10           10          kubernetes.io/os=linux   483d

NAME                                              READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/cluster-image-registry-operator   1/1     1            1           483d
deployment.apps/image-registry                    1/1     1            1           483d

NAME                                                         DESIRED   CURRENT   READY   AGE
replicaset.apps/cluster-image-registry-operator-74fcc9f669   0         0         0       483d
replicaset.apps/cluster-image-registry-operator-7f69b9db5d   1         1         1       405d
replicaset.apps/cluster-image-registry-operator-fd7d9cbf9    0         0         0       419d
replicaset.apps/image-registry-7476b49c58                    1         1         1       88d
replicaset.apps/image-registry-847fc7fb97                    0         0         0       483d
replicaset.apps/image-registry-856c9cd9bb                    0         0         0       419d
replicaset.apps/image-registry-86cd4c598f                    0         0         0       88d
replicaset.apps/image-registry-94b6b4885                     0         0         0       483d

NAME                         SCHEDULE    SUSPEND   ACTIVE   LAST SCHEDULE   AGE
cronjob.batch/image-pruner   0 0 * * *   False     0        16h             483d

NAME                              COMPLETIONS   DURATION   AGE
job.batch/image-pruner-28644480   1/1           9s         2d16h
job.batch/image-pruner-28645920   1/1           8s         40h
job.batch/image-pruner-28647360   1/1           8s         16h
```

Le registry est un catalogue d\'images docker versionné par des tags.
Chaque version de cette image hébergée sur des catalogues extérieurs
(dockerhub.io, quay.io, etc\...) à laquelle fera appel un `deployment`
sera téléchargée et stockée sur ce catalogue interne. Il est alors
possible de créer des règles qui permettront de surveiller et de
comparer la version de l\'image en interne avec celle du registry
distant, et en fonction de déclencher un nouvel import.

De la même façon, on peut y stocker des images buildées en interne,
avant de les publier sur un catalogue extérieur.

## Accessibilité

### clients

On y accède indifféremment avec `docker` ou `podman`.

### users

Si on n\'utilise pas le superutilisateur `kubeadmin`, il faut ajouter à
un simple utilisateur certains droits pour accéder au registry:

``` /bash
oc policy add-role-to-user registry-viewer sblanchet
oc policy add-role-to-user registry-editor sblanchet
```

### interne

Par défaut ce registry est uniquement accessible en interne sur le
service `image-registry.openshift-image-registry.svc:5000`. Pour
utiliser le service interne, il faut se connecter alors depuis un
worker. On peut considérer cette façon de faire comme un mode dépannage
rapide, en négligeant le support du TLS.

``` /bash
oc debug nodes/v212-t4k2k-worker-0-dgjzp
chroot /host
oc login https://api.orchidee.okd-dev.abes.fr:6443 -u sblanchet -n <project_name>
podman login -u sblanchet -p $(oc whoami -t) image-registry.openshift-image-registry.svc:5000 --tls-verify=false
```

### externe

L\'idéal est d\'avoir le client `podman` ou `docker` directement sur son
poste de travail, ce qui permet notamment de configurer une bonne fois
pour toutes la couche de sécurité TLS.

Par défaut, le service `image-registry` n\'est pas exposé pour un accès
à l\'extérieur du cluster. Il faut donc l\'activer
(<https://docs.openshift.com/container-platform/4.13/registry/securing-exposing-registry.html>
):

``` /bash
oc login https://api.orchidee.okd-dev.abes.fr:6443 -u kubeadmin -n <project_name>
oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge

oc get route default-route -n openshift-image-registry -o json | jq -r .spec.host
NAME                                     HOST/PORT                                                              PATH   SERVICES         PORT    TERMINATION   WILDCARD
route.route.openshift.io/default-route   default-route-openshift-image-registry.apps.orchidee.okd-dev.abes.fr          image-registry   <all>   reencrypt     None

HOST=$(oc get route default-route -n openshift-image-registry -o json | jq -r .spec.host)
```

On peut alors s\'y connecter simplement (sans TLS) ainsi;

``` /bash
podman login -u $(oc whoami) -p $(oc whoami -t) default-route-openshift-image-registry.apps.orchidee.okd-dev.abes.fr --tls-verify=false
Login Succeeded!
```

### Support du TLS

#### Création du répertoire contenant le certificat

Par défaut, le répertoire `certs.d` n\'existe pas, il faut donc le
créer, ainsi que le sous-répertoire qui contient l\'url qui sera
appelée, ici
`default-route-openshift-image-registry.apps.orchidee.okd-dev.abes.fr`

-   podman

``` /bash
mkdir -p /etc/containers/certs.d/${HOST}
```

-   docker

``` /bash
mkdir -p /etc/docker/certs.d/${HOST}
```

#### récupération du certificat root du routeur ingress

``` /bash
oc get secret -n openshift-ingress  router-certs-default -o go-template='{{index .data "tls.crt"}}' | base64 -d | sudo tee /etc/containers/certs.d/${HOST}/${HOST}.crt  > /dev/null
# ou bien 
oc extract secret/router-certs-default -n openshift-ingress --to=/etc/containers/certs.d/$HOST/
oc get secret -n openshift-ingress  router-certs-default -o go-template='{{index .data "tls.crt"}}' | base64 -d | sudo tee /etc/docker/certs.d/${HOST}/${HOST}.crt  > /dev/null
# ou bien
oc extract secret/router-certs-default -n openshift-ingress --to=/etc/docker/certs.d/$HOST/
```

#### Connexion

``` /bash
podman login -u $(oc whoami) -p $(oc whoami -t) $HOST
docker login -u $(oc whoami) -p $(oc whoami -t) $HOST
```

Pour mémoire, même si cela a peut d\'intérêt en utilisant la méthode
ci-dessus, on peut aussi se connecter en indiquant un certificat en
particulier:

-   podman

``` /bash
podman login default-route-openshift-image-registry.apps.orchidee.okd-dev.abes.fr --tls-verify --cert-dir /etc/containers/certs.d/
```

-   docker

Il faut d\'abord rajouter le certificat ca dans /etc/ssl/certs en
changeant l\'option `pem` par l\'extension `crt`

``` /bash
cd /etc/ssl/certs
oc get secret -n openshift-ingress  router-certs-default -o go-template='{{index .data "tls.crt"}}' | base64 -d | sudo tee ${HOST}.crt  > /dev/null
mv apps-orchidee-okd-dev-abes-fr.pem apps-orchidee-okd-dev-abes-fr.crt
```

    docker --tlscacert /etc/docker/certs.d/default-route-openshift-image-registry.apps.orchidee.okd-dev.abes.fr.crt login default-route-openshift-image-registry.apps.orchidee.okd-dev.abes.fr

## Quay.io

<https://docs.redhat.com/en/documentation/red_hat_quay/3/html/deploying_the_red_hat_quay_operator_on_openshift_container_platform/operator-preconfigure#enabling-general-api-access>

`Quay.io` est le service de registry en ligne proposé par RedHat. Il est
également disponible en version on premise installable sous OKD sous
forme d\'operateur.

### Installation

Operator -\> OperatorHub -\> Red Hat Quay Bridge Operator
L\'installation peut se faire dans un namespace précis, mais il est
conseillé de le faire dans tous les namespaces. Dans les exemples
suivant, on crée le namespace `quay-registry` au moment de
l\'installation de l\'opérateur.

### Vérification

``` /bash
oc get all -n quay-registry 
NAME                                                 READY   STATUS      RESTARTS   AGE
pod/first-registry-clair-app-7c4bb8758c-brsjj        1/1     Running     0          3d1h
pod/first-registry-clair-app-b9f57dfbc-cv8gl         0/1     Pending     0          4d4h
pod/first-registry-clair-app-b9f57dfbc-jtnb4         0/1     Pending     0          2d23h
pod/first-registry-clair-postgres-56b74fcbc4-ljs7z   1/1     Running     0          4d3h
pod/first-registry-quay-app-56bcf564db-sjlgs         0/1     Pending     0          4d1h
pod/first-registry-quay-app-6f6fc5c598-nwtx9         0/1     Pending     0          2d23h
pod/first-registry-quay-app-6f6fc5c598-rr9km         1/1     Running     0          3d2h
pod/first-registry-quay-app-upgrade-ds4r9            0/1     Completed   3          4d4h
pod/first-registry-quay-database-6c7c878bdb-jxwtv    1/1     Running     0          4d4h
pod/first-registry-quay-mirror-b8df68446-clpph       1/1     Running     0          3d2h
pod/first-registry-quay-mirror-b8df68446-fmxsm       1/1     Running     0          3d2h
pod/first-registry-quay-redis-6f74bffb6d-dpcnj       1/1     Running     0          4d3h

NAME                                    TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)                             AGE
service/first-registry-clair-app        ClusterIP   172.30.159.44    <none>        80/TCP,8089/TCP                     4d4h
service/first-registry-clair-postgres   ClusterIP   172.30.50.220    <none>        5432/TCP                            4d4h
service/first-registry-quay-app         ClusterIP   172.30.67.169    <none>        443/TCP,80/TCP,8081/TCP,55443/TCP   4d4h
service/first-registry-quay-database    ClusterIP   172.30.86.243    <none>        5432/TCP                            4d4h
service/first-registry-quay-metrics     ClusterIP   172.30.227.132   <none>        9091/TCP                            4d4h
service/first-registry-quay-redis       ClusterIP   172.30.236.180   <none>        6379/TCP                            4d4h

NAME                                            READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/first-registry-clair-app        1/2     2            1           4d4h
deployment.apps/first-registry-clair-postgres   1/1     1            1           4d4h
deployment.apps/first-registry-quay-app         1/2     2            1           4d4h
deployment.apps/first-registry-quay-database    1/1     1            1           4d4h
deployment.apps/first-registry-quay-mirror      2/2     2            2           4d4h
deployment.apps/first-registry-quay-redis       1/1     1            1           4d4h

NAME                                                       DESIRED   CURRENT   READY   AGE
replicaset.apps/first-registry-clair-app-7c4bb8758c        1         1         1       4d4h
replicaset.apps/first-registry-clair-app-b9f57dfbc         2         2         0       4d4h
replicaset.apps/first-registry-clair-postgres-569f974c98   0         0         0       4d4h
replicaset.apps/first-registry-clair-postgres-56b74fcbc4   1         1         1       4d4h
replicaset.apps/first-registry-quay-app-56bcf564db         1         1         0       4d1h
replicaset.apps/first-registry-quay-app-5c88898b8b         0         0         0       4d4h
replicaset.apps/first-registry-quay-app-655c5fdcfd         0         0         0       4d4h
replicaset.apps/first-registry-quay-app-6f6fc5c598         2         2         1       3d2h
replicaset.apps/first-registry-quay-database-6c7c878bdb    1         1         1       4d4h
replicaset.apps/first-registry-quay-database-8495f75c58    0         0         0       4d4h
replicaset.apps/first-registry-quay-mirror-64654b76db      0         0         0       4d1h
replicaset.apps/first-registry-quay-mirror-655496f946      0         0         0       4d4h
replicaset.apps/first-registry-quay-mirror-b8df68446       2         2         2       3d2h
replicaset.apps/first-registry-quay-mirror-f5656f4d4       0         0         0       4d4h
replicaset.apps/first-registry-quay-redis-6f74bffb6d       1         1         1       4d4h
replicaset.apps/first-registry-quay-redis-7556559476       0         0         0       4d4h

NAME                                                             REFERENCE                               TARGETS           MINPODS   MAXPODS   REPLICAS   AGE
horizontalpodautoscaler.autoscaling/first-registry-clair-app     Deployment/first-registry-clair-app     23%/90%, 0%/90%   2         10        2          4d4h
horizontalpodautoscaler.autoscaling/first-registry-quay-app      Deployment/first-registry-quay-app      47%/90%, 3%/90%   2         20        2          4d4h
horizontalpodautoscaler.autoscaling/first-registry-quay-mirror   Deployment/first-registry-quay-mirror   35%/90%, 0%/90%   2         20        2          4d4h

NAME                                        COMPLETIONS   DURATION   AGE
job.batch/first-registry-quay-app-upgrade   1/1           19m        4d4h

NAME                                                   HOST/PORT                                                                 PATH   SERVICES                  PORT   TERMINATION     WILDCARD
route.route.openshift.io/first-registry-quay           first-registry-quay-quay-registry.apps.orchidee.okd-dev.abes.fr                  first-registry-quay-app   http   edge/Redirect   None
route.route.openshift.io/first-registry-quay-builder   first-registry-quay-builder-quay-registry.apps.orchidee.okd-dev.abes.fr          first-registry-quay-app   grpc   edge/Redirect   None
```

Cette fois, la route du registry quay ainsi crée est donc:

``` /bash
HOST=first-registry-quay-quay-registry.apps.orchidee.okd-dev.abes.fr
```

Configuration du registry par défaut:

``` /bash
oc get -n quay-registry quayregistries.quay.redhat.com -o yaml
apiVersion: v1
items:
- apiVersion: quay.redhat.com/v1
  kind: QuayRegistry
  metadata:
    creationTimestamp: "2024-06-17T12:50:04Z"
    finalizers:
    - quay-operator/finalizer
    generation: 2
    name: first-registry
    namespace: quay-registry
    resourceVersion: "624060656"
    uid: 22049a1a-4d99-48ed-a495-fe1a5373c9a1
  spec:
    components:
    - kind: clair
      managed: true
    - kind: postgres
      managed: true
    - kind: objectstorage
      managed: true
    - kind: redis
      managed: true
    - kind: horizontalpodautoscaler
      managed: true
    - kind: route
      managed: true
    - kind: mirror
      managed: true
    - kind: monitoring
      managed: true
    - kind: tls
      managed: true
    - kind: quay
      managed: true
    - kind: clairpostgres
      managed: true
    configBundleSecret: first-registry-config-bundle-wql84
```

La mention `managed` permet de se servir des ressources du cluster okd.
Si ces ressources étaient positionnées à `false`, alors il faudrait
manuellement configurer tous ces services.

`configBundleSecret` est la référence au fichier de configuration de
quay qui est `config.yaml`. Celui par défaut a été directement généré
par l\'opérateur avec des valeurs par défaut et mis sous la forme de
`secrets`

``` /bash
oc extract secrets/first-registry-config-bundle-wql84 -n quay-registry --to=-
# config.yaml
ALLOW_PULLS_WITHOUT_STRICT_LOGGING: false
AUTHENTICATION_TYPE: Database
DEFAULT_TAG_EXPIRATION: 2w
ENTERPRISE_LOGO_URL: /static/img/RH_Logo_Quay_Black_UX-horizontal.svg
FEATURE_BUILD_SUPPORT: false
FEATURE_DIRECT_LOGIN: true
FEATURE_MAILING: false
REGISTRY_TITLE: Red Hat Quay
REGISTRY_TITLE_SHORT: Red Hat Quay
SETUP_COMPLETE: true
TAG_EXPIRATION_OPTIONS:
- 2w
TEAM_RESYNC_STALE_TIME: 60m
TESTING: false
FEATURE_USER_INITIALIZE: true
SUPER_USERS:
     -  quayadmin
BROWSER_API_CALLS_XHR_ONLY: false
```

Pour modifier ces options, le plus simple est de passer par l\'UI.
Sinon, il faut créer un fichier `config.yaml` avec ces options en clair.

``` /bash
touch config.yaml
----
BROWSER_API_CALLS_XHR_ONLY: true
----
```

et générer le secret à partir du fichier:

``` /bash
oc create secret generic --from-file config.yaml=./config.yaml first-registry-config-bundle-wql84
```

et on redémarre les containers `quay-app` et `quay-clair` pour que la
nouvelle configuration soit prise en compte.

Le paramètre `BROWSER_API_CALLS_XHR_ONLY: false` permet d\'indiquer
qu\'on peut consulter l\'API depuis l\'extérieur, notamment avec swagger
ou depuis un navigateur:

``` /bash
sudo podman run -p 8888:8080 -e API_URL=https://$SERVER_HOSTNAME:8443/api/v1/discovery docker.io/swaggerapi/swagger-ui
```

### Gestion des utilisateurs

<https://docs.redhat.com/en/documentation/red_hat_quay/3/html/deploying_the_red_hat_quay_operator_on_openshift_container_platform/operator-deploy#using-the-api-to-create-first-user>

Par défaut, il n\'y a pas d\'utilisateur. La première chose est donc
d\'en créer grâce à l\'option `FEATURE_USER_INITIALIZE: true`

Nous allons de plus en profiter pour créer l\'utilisateur admin
`quayadmin` déclaré avec à l\'initialisation grâce à l\'option
`SUPER_USERS`.

``` /bash
curl -X POST -k https://first-registry-quay-quay-registry.apps.orchidee.okd-dev.abes.fr/api/v1/user/initialize --header 'Content-Type: application/json' --data '{ "username": "quayadmin2", "password":"", "email": "quayadmin2@example.com", "access_token": true}'
```

On peut alors se connecter à l\'api avec ce superuser

``` /bash
sudo podman login -u quayadmin -p "" https://first-registry-quay-quay-registry.apps.orchidee.okd-dev.abes.fr --tls-verify=false
sudo docker login -u quayadmin -p "" https://first-registry-quay-quay-registry.apps.orchidee.okd-dev.abes.fr --tls-verify=false
```

Si on veut utiliser l\'option TLS, alors il faut procéder de la même
manière que pour le registry interne par défaut, à savoir récupérer le
certificat CA du routeur ingress et le copier avec l\'extension `crt`
dans
`/etc/docker/certs.d/first-registry-quay-quay-registry.apps.orchidee.okd-dev.abes.fr/`

``` /bash
oc extract secret/router-certs-default -n openshift-ingress --to=/etc/containers/certs.d/first-registry-quay-quay-registry.apps.orchidee.okd-dev.abes.fr/
oc extract secret/router-certs-default -n openshift-ingress --to=/etc/docker/certs.d/first-registry-quay-quay-registry.apps.orchidee.okd-dev.abes.fr/
```

Sinon, on peut toujours créer un compte directement depuis l\'interface
web.

## Exemple de manipulation du registry une fois logué

### Avec le registry OKD

#### objectif

L\'objectif est d\'uploader une image existante dans le repository local
dans le registry OKD

<https://www.youtube.com/watch?v=r5VzXvvkiL4&ab_channel=debianmaster>

#### Mise en pratique

**On liste l\'image contenue dans le registry docker local**

``` /bash
docker images
...
registry.gitlab.com/nfdi4culture/ta1-data-enrichment/openrefine-wikibase  1.1.0 2512c8cf3084   11 months ago   284MB
...
```

**On crée une imageStream correspondante**

``` /bash
oc create is openrefine-wikibase
```

**On tague l\'image docker avec la syntaxe
\<registry_address\>/namespace/\<is_name\>**

``` /bash
docker tag  registry.gitlab.com/nfdi4culture/ta1-data-enrichment/openrefine-wikibase:1.1.0 default-route-openshift-image-registry.apps.orchidee.okd-dev.abes.fr/movies-docker-beta/openrefine-wikibase
```

**On pousse l\'image précédemment taguée dans okd**

``` /bash
docker push default-route-openshift-image-registry.apps.orchidee.okd-dev.abes.fr/movies-docker-beta/openrefine-wikibase
```

### Avec Quay

La tutoriel qui suit est celle proposée par l\'interface de quay pour
s\'approprier l\'outil.

-   Logging into Red Hat Quay from the Docker CLI
-   Starting a container
-   Creating images from a container
-   Pushing a repository to Red Hat Quay
-   Viewing a repository
-   Changing a repository\'s permissions

#### Logging into Red Hat Quay from the Docker CLI

``` /
docker login -u quayadmin first-registry-quay-quay-registry.apps.orchidee.okd-dev.abes.fr
```

#### Démarrage d\'un container

``` /bash
docker run busybox echo "fun" > newfile
docker ps -l
CONTAINER ID        IMAGE               COMMAND             CREATED
07f2065197ef          busybox:latest        echo fun            31 seconds ago
```

#### Création d\'une image

L\'idée dans cette étape est de récupérer une image depuis dockerhub, de
la modifier, et de commiter cette modification en local en lui
attribuant un tag qui aura la forme `<registry>/<user>/<repository>` du
registry distant.

``` /bash
docker commit 07f2065197ef first-registry-quay-quay-registry.apps.orchidee.okd-dev.abes.fr/quayadmin/myfirstrepo
```

On aurait pu uniquement taguer cette image sans la modifier de la façon
suivante

``` /bash
docker tag busybox:latest $HOST/quayadmin/myfirstrepo
```

#### Push the image to Red Hat Quay

``` /bash
docker push first-registry-quay-quay-registry.apps.orchidee.okd-dev.abes.fr/quayadmin/myfirstrepo
```
