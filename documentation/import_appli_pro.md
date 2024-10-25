# OKD: Conversion et import d\'une appli Docker dans k8s

## Objectif

Adapter une application Docker existante tournant en production sur
`diplotaxisX-prod` pour `k8s` sur un environnement OKD

## Application choisie

`Qualimarc` est l\'application la plus récente et la plus complète
correspondant à l\'ensemble des cas de figure rencontrés sur Docker:

-   backend:

       * qualimarc-api
       * qualimarc-batch
    * frontend:
      * qualimarc-front
    * BDD postgres
      * qualimarc-db
      * qualimarc-db-adminer
      * qualimarc-db-dumper
    * watchtower
      * qualimarc-watchtower 
    * variables d'environnement
    * volumes persistants

Le projet Github source:
https://github.com/orgs/abes-esr/repositories?q=qualimarc&type=all&language=&sort=

Le fichier docker-compose source
<https://github.com/abes-esr/qualimarc-docker/blob/develop/docker-compose.yml>

## Prérequis

### oc

``` /bash
wget https://github.com/okd-project/okd/releases/download/4.12.0-0.okd-2023-02-18-033438/openshift-client-linux-4.12.0-0.okd-2023-02-18-033438.tar.gz
tar xvzf openshift-client-linux-4.12.0-0.okd-2023-02-18-033438.tar.gz
mv {kubectl,oc} /usr/local/bin/
```

### docker-compose

``` /bash
curl -L "https://github.com/docker/compose/releases/download/v2.16.0/docker-compose-linux-x86_64" -o /usr/local/bin/docker-compose
```

### kompose

L\'import de `Qualimarc dans OKD` réside dans l\'adaptation du fichier
`docker-compose.yaml` en fichiers manifest d\'objets k8s grâce à
l\'outil `kompose`.

``` /bash
curl -L https://github.com/kubernetes/kompose/releases/download/v1.28.0/kompose-linux-amd64 -o /usr/local/bin/kompose
```

### droits d\'exécution

``` /bash
chmod +x /usr/local/bin/{oc,kompose,docker-compose}
```

## Connexion à l\'environnement OKD de destination

La connexion au serveur OKD peut se faire de plusieurs manières. Les
paramètres se trouvent dans le répertoire d\'installation du cluster:

``` /bash
~<install_dir>/auth/
```

#### fichier kubeconfig

``` /bash
export KUBECONFIG=~install_dir>/auth/kubeconfig
```

#### login kubeadmin

``` /bash
oc login -u kubeadmin -p  $(echo ~<install_dir>/auth/kubeadmin-password)  https://api.orchidee.v102.abes.fr:6443
```

Qand on se connecte avec un login, cela permet d\'obtenir un `token`. Ce
token peut être la seule façon de s\'authentifier par la suite,
notamment avec podman.

``` /bash
oc whoami -t
sha256~X
```

Dans les deux cas de figure, on est connecté avec le super utilisateur
`kubeadmin`:

``` /bash
oc whoami
```

#### login avec slogin sur LDAP

Pour se connecter depuis LDAP et rafraîchir son fichier *kubeconfig*
pour prendre en compte\
le user avec lequel on est connecté sur le namespace *default*

``` /bash
oc login -u slogin
oc config set-context `oc config current-context` --namespace=default
```

## Etapes

     * Création du projet

``` /bash
oc new-project qualimarc
```

-   Elevation des privilèges du `service account` `default` pour les
    droits root de certains containers:

``` /bash
oc adm policy add-scc-to-user anyuid -z default
```

-   Création d\'un secret qui permet de se connecter au registry
    `dockerhub` sans limites de connexions

``` /bash
oc create secret docker-registry docker.io --docker-server=docker.io --docker-username= --docker-password=
```

-   Rajout de ce secret au `service account` `default`

    oc secrets link default docker.io --for=pull
    oc get sa default -o yaml

-   Téléchargement des sources du projet

``` /bash
git clone https://github.com/abes-esr/qualimarc-docker.git
cd qualimarc
```

-   import du fichier `env` de l\'environnement choisi

``` /bash
rsync -av root@diplotaxis1-dev.v106.abes.fr:/opt/pod/qualimarc-docker/.env .
```

-   Génération du fichier `docker-compose-resolved.yml` contenant la
    valeur des variables `.env`

``` /bash
docker-compose config > docker-compose-resolved.yml
```

-   Nettoyage des composants inutiles (notamment `mem_limit` et
    `qualimarc-watchtower`) qui ne fonctionne qu\'en environnement
    docker

``` /bash
docker-compose -f docker-compose-resolved.yml convert --format json \
| jq 'del (.services[].command)' \
| jq 'del (.services[].entrypoint)' \
| jq 'del (.services."qualimarc-watchtower")' \
| jq 'del (.services[].mem_limit)'\
| jq  '.services."qualimarc-db" += {ports: [{"mode": "ingress", "target": 5432, "published": 5432, "protocol": "tcp"}]}' \
| docker-compose -f - convert > docker-compose-resolved-cleaned.yml
```

-   **optionnel** Ajout du port `5432` pour que le service
    `qualimarc-db` soit directement disponible

``` /bash
docker-compose -f docker-compose-resolved.yml convert --format json | jq  '.services."qualimarc-db" += {ports: [{"mode": "ingress", "target": 5432, "published": 5432, "protocol": "tcp"}]}'
# ou bien
docker-compose -f docker-compose-resolved.yml convert --format json | jq --argjson json '{ports: [{"mode": "ingress", "target": 5432, "published": 5432, "protocol": "tcp"}]}' '.services."qualimarc-db" += {ports: $json}'
```

-   Conversion du fichier docker-compose-resolved-cleaned.yml en
    Manifests k8s

``` /bash
kompose -f docker-compose-resolved-cleaned.yml convert --provider openshift
INFO OpenShift file "qualimarc-api-service.yaml" created 
INFO OpenShift file "qualimarc-db-service.yaml" created 
INFO OpenShift file "qualimarc-db-adminer-service.yaml" created 
INFO OpenShift file "qualimarc-front-service.yaml" created 
INFO OpenShift file "qualimarc-api-deploymentconfig.yaml" created 
INFO OpenShift file "qualimarc-api-imagestream.yaml" created 
INFO OpenShift file "qualimarc-batch-deploymentconfig.yaml" created 
INFO OpenShift file "qualimarc-batch-imagestream.yaml" created 
INFO OpenShift file "qualimarc-batch-claim0-persistentvolumeclaim.yaml" created 
INFO OpenShift file "qualimarc-db-deploymentconfig.yaml" created 
INFO OpenShift file "qualimarc-db-imagestream.yaml" created 
INFO OpenShift file "qualimarc-db-claim0-persistentvolumeclaim.yaml" created 
INFO OpenShift file "qualimarc-db-adminer-deploymentconfig.yaml" created 
INFO OpenShift file "qualimarc-db-adminer-imagestream.yaml" created 
INFO OpenShift file "qualimarc-db-dumper-deploymentconfig.yaml" created 
INFO OpenShift file "qualimarc-db-dumper-imagestream.yaml" created 
INFO OpenShift file "qualimarc-db-dumper-claim0-persistentvolumeclaim.yaml" created 
INFO OpenShift file "qualimarc-front-deploymentconfig.yaml" created 
INFO OpenShift file "qualimarc-front-imagestream.yaml" created 
INFO OpenShift file "qualimarc-watchtower-deploymentconfig.yaml" created 
INFO OpenShift file "qualimarc-watchtower-imagestream.yaml" created 
INFO OpenShift file "qualimarc-watchtower-claim0-persistentvolumeclaim.yaml" created 
```

-   Remplacement de la bonne version d\'api pour les manifests
    `imagestream` et `deploymentconfig`

``` /bash
sed -i 's/apiVersion: v1/apiVersion: image.openshift.io\/v1/g' *imagestream.yaml 
sed -i 's/apiVersion: v1/apiVersion: apps.openshift.io\/v1/g' *deploymentconfig.yaml
```

-   Création du service `qualimarc-db-service.yaml`

``` /bash
oc create service clusterip qualimarc-db-postgres --tcp=5432
oc set selector svc qualimarc-db-postgres 'io.kompose.service=qualimarc-db'
#ou bien
oc create service clusterip my-svc -o yaml --dry-run | oc set selector --local -f - 'environment=qa' -o yaml | oc create -f -
```

Remarque: ce service est indispensable pour que le pod `qualimarc-front`
soit en mesure d\'appeler la base postgres. Si ce service n\'a pas été
créé par `kompose`, c\'est dû au fait que le container `qualimarc-db` du
fichier original `docker-compose.yaml` n\'avait pas de ports de défini.
On aurait pu le rajouter dans le fichier avant la conversion:

``` /yaml
  qualimarc-db:
    image: abesesr/postgres-fr_fr:15.1.0
    container_name: qualimarc-db
    restart: unless-stopped
    mem_limit: ${MEM_LIMIT}
    environment:
      # cf https://github.com/docker-library/docs/blob/master/postgres/README.md#environment-variables
      POSTGRES_DB: "qualimarc"
      POSTGRES_USER: ${QUALIMARC_DB_POSTGRES_USER}
      POSTGRES_PASSWORD: ${QUALIMARC_DB_POSTGRES_PASSWORD}
    ports:
      - 5432:5432
    volumes:
      - ./volumes/qualimarc-db/pgdata/:/var/lib/postgresql/data/
```

-   Il ne reste qu\'à appliquer les manifests dans OKD

``` /bash
oc apply -f 'qualimarc-*.yaml'
```

-   On vérifie que les containers se créent bien

``` /bash
oc get all
oc get pods
```

-   Il faut vérifier que les images se téléchargent correctement depuis
    leurs registries d\'origine

``` /bash
oc get is
```

Si ce n\'est pas le cas, aucun container ne se lancera.

-   Volumes : par défaut les PVC (permanent Volume Claim) de 100M sont
    créés.\
    Pour augmenter leur taille, passer par un patch :

``` /bash
oc patch pvc <pvc_name> -p '{"spec":{"resources":{"requests":{"storage":"4Gi"}}}}'
```

-   Cas de du container de la bdd postgres `qualimarc-db`

Le déploiement du container `qualimarc-db` ne se lance pas du fait que
la base de données n\'est pas initialisée. Il faut donc importer le
contenu initial depuis le volume du diplotaxis initial. Pour cela il
n\'est pas indispensable que le container soit démarré, il suffit de
rentrer en mode `debug` et d\'initier la copie.

``` /bash
oc debug qualimarc-db-4-c8gpn
bash
apt update && apt install rsync openssh-client -y
rsync -av diplotaxis1-dev.v106.abes.fr:/opt/pod/qualimarc-docker/volumes/qualimarc-db/pgdata/ /var/lib/postgresql/data/
```

Une fois la copie effectuée avec succès, il faut relancer le déploiemen
du container:

``` /bash
oc rollout retry dc qualimarc-db
oc get pods
```

Une fois le pod postgres up, l\'ensemble des pods qui en dépendent
devient aussi up. Si ce n\'est pas le cas, il faut faire un rollout de
l\'ensemble des pods qui ne démarrent pas, ou bien réappliquer les
manifests un par un.

-   Pour accéder à l\'url, il faut exposer le service du container
    `qualimarc-front`, ce qui aura pour effet de générer une route DNS
    par l\'ingress d\'OKD:

``` /bash
oc expose service/qualimarc-front
oc expose service/qualimarc-api
oc expose service/qualimarc-db-adminer
oc get route
qualimarc  qualimarc-qualimarc2.apps.orchidee.v102.abes.fr  qualimarc-front 11080 None
```

-   On teste le webservice sur son exposition publique:

``` /bash
curl http://qualimarc-api-qualimarc-sire.apps.orchidee.v102.abes.fr/api/v1/statusApplication
```

## Debug

``` /bash
oc debug <pod>
oc log <pod>
oc rsh pod/<pod>
oc rsh node/<node>
oc describe <pod>
oc describe dc/<dc>
```

## Remplacement de WatchTower

`Watchtower` est l\'application (également fournie sous forme de
container docker) qui permet de détecter une nouvelle mise à jour d\'une
image docker sur `DockerHub` et de la déployer sur `diplotaxis`.

Le daemon `docker` ayant été remplacé par `crio` sous `Kubernetes`, il
faut donc utiliser l\'outil `keel` pour arriver au même niveau de
fonctionnalité.

Pour plus de détail, suivre - [Keel remplaçant de watchtower](keel.md)
