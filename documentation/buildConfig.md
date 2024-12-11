# CI/CD avec les APIs natives Openshift (buildConfig)

`buildConfig` est la solution la plus directe et clé en main native et
propre à Openshift.

<https://docs.openshift.com/container-platform/4.9/cicd/builds/creating-build-inputs.html#builds-docker-credentials-private-registries_creating-build-inputs>

<https://docs.redhat.com/en/documentation/openshift_container_platform/4.1/html/builds/basic-build-operations#builds-basic-access-build-verbosity_basic-build-operations>

## Workflow

L\'objectif est d\'obtenir une image et de gérer le cycle de vie de
cette image.

-   `CI`: construction de l\'image par l\'outil interne au cluster
    Openshift **Builda** à partir du trigger de commit git
-   `CD`: déploiement de l\'image dans le `deploymentConfig` à partir d
    `imageStream`

A chaque fois que du code change il y a rebuild de l\'image qui est
pushée dans le registry L\'imageStream détecte le changement de digest
dans le registry et force le redéploiement du deploymentConfig

## Custom Resource Definition

Openshift propose des d\'API qui lui sont propres:

-   **imageStream**: `image.openshift.io/v1`

L\'imageStream (**is**) a pour objectif d\'établir un lien de
correspondance entre le tag d\'une image locale et celle d\'un registry
quelconque

-   **deploymentConfig**: `apps.openshift.io/v1`

C\'est l\'API responsable du déploiement des containers développée par
RedHat, en concurrence avec `deployment` native à Kubernetes. **dc**
supporte engre autre nativement **imageStream**. On aurait pu cependant
arriver au même résultat avec `Deployment`, voir la partie
\"\"complément\"\".

-   **buildConfig**: `build.openshift.io/v1`

Nous allons donc proposer une première façon de présenter un CI/CD avec
une solution native à Openshift.

**NOTE**: Il existe un bug dans la génération des fichiers `buildConfig`
puisque la version de l\'api `v1` n\'est pas celle attendue
`build.openshift.io/v1`. Il faut donc remplacer cela avec une commande:

``` /bash
for i in $(ls |grep buildconfig); do yq -i '.apiVersion="build.openshift.io/v1"' $i; done
for i in $(ls |grep image); do yq -i '.apiVersion="image.openshift.io/v1"' $i; done
```

## Méthode Kompose

Pour utiliser le CI/CD natif d\'Openshift, il faut d\'abord convertir
les directives de construction d\'image docker-compose.yml en directive
`buildConfig`. Pour ce faire, nous utiliserons `kompose` en mode
`Openshift`

``` /bash
git clone https://github.com/abes-esr/abesstp-docker.git
docker-compose config | kompose -f - convert --build build-config --provider OpenShift
```

avec notammentle résultat pour le service **abesstp-web** :

``` /bash
abesstp-web-deploymentconfig.yaml
abesstp-web-imagestream.yaml
abesstp-web-buildconfig.yaml
...
```

## Analyse du buildconfig.yaml

``` /bash
cat abesstp-web-buildconfig.yaml
```

``` /yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  labels:
    io.kompose.service: abesstp-web
  name: abesstp-web
spec:
  output:
    to:
      kind: ImageStreamTag
      name: abesstp-web:php-5.6.40-apache
  runPolicy: Serial
  source:
    contextDir: images/abesstp-web
    git:
      ref: patch-1
      uri: https://github.com/natman/abesstp-docker.git
    type: Git
  strategy:
    dockerStrategy:
      dockerfilePath: Dockerfile
      env:
      - name: BUILD_LOGLEVEL
        value: "5"
      pullSecret:
        name: docker.io
    type: Docker
  triggers:
  - type: ConfigChange
```

### imageStream

La CR `buildConfig` est étroitement liée à la CR `imageStream` dans un
fonctionnement natif à Openshift. Elle se charge entre autre de taguer
les images buildées dans `ImageStream` avec la CR `imageStreamTag`

### git

Les paramètres par défaut git, source et branche, sont ceux repris
depuis le répertoire courant `.git/config`.

### pullSecret

Pour éviter des message d\'erreur du type \"reach rate limit\"
lorsqu\'on cherche à puller des images depuis DockerHub, on peut
renseigner une authentification sous forme de secret. Pour ce faire, on
procède ainsi:

-   Soit à partir d\'une authentification docker existante sur le poste
    local:

``` /bash
oc create secret generic docker.io --from-file=.dockerconfigjson=<path>.docker/config.json> --type=kubernetes.io/dockerconfigjson
```

-   Soit en définissant manuellement le secret

``` /bash
oc create secret docker-registry docker.io --docker-server=docker.io --docker-username=picabesesr --docker-password=**CHANGED**
```

Puis on lie ce secret au `buildConfig`:

``` /bash
oc set build-secret --pull bc/abesstp-web docker.io
```

et on déclare ce secret comme fonction de pull pour le service account
voulu:

``` /bash
oc secrets link default docker.io --for=pull
```

### trigger de déclenchement

Un nouveau build se déclenche sur la base du changement de configuration
des sources git.

### loglevel

``` /yaml
dockerStrategy:
...
  env:
    - name: "BUILD_LOGLEVEL"
      value: "5" 
```

### Lancement du build

Le build initial de l\'image se fait automatiquement après création du
manifest.

On peut également le lancer à la main:

``` /bash
oc start-build abesstp-web --follow
oc get build
oc describe build abesstp-web-9
oc logs -f bc/abesstp-web 
oc cancel-build

```

L\'image est automatiquement poussée dans le registry interne
`image-registry.openshift-image-registry.svc:5000`. On vérifie sa
présence:

``` /bash
oc get images| grep image-registry.openshift-image-registry.svc:5000
oc describe images sha256:1cfb09aa043a3c4d24baa984879d16decc7be038501f35465c0be59dd95c44bb
```

## Complément: utilisation de Deployment à la place de DeploymentConfig

On aurait pu utiliser l\'API Kubernetes `Deployment` à la place de
`DeploymentConfig`.

Pour utiliser l\'API `imageStream` avec `Deployment`, il faut rendre
`imageStream` résolvable par les objets natifs:

``` /bash
oc set image-lookup abesstp-web --enabled=true
```

En ce qui concerne les triggers, il faut ajouter des annotations à
l\'objet `deploy` pour fairer référence à \'\'imageStream:

``` /bash
oc set triggers deploy/abesstp-web --from-image=abesstp-web:php-5.6.40-apache -c abesstp-web
```
