# Utilisation d\'ImageStream avec le deployment k8s

## Définition

La resource Openshift `imageStream` n\'est pas indispensable, mais elle
permet d\'amener des améliorations dans l\'accès à un registry en tant
qu\'interface. Elle agit notamment comme un reflet du registry qu\'elle
surveille, garantissant l\'accès au déploiement de l\'image désirée. De
plus, elle permet de surveiller l\'état d\'une image et de déclencher un
redéploiement.

## Sans imageStream

### Registry externe (docker.io)

#### Mise en oeuvre

Si on choisit de s\'en passer, alors il suffit de faire pointer l\'image
voulue dans le `deployment` vers le registry correspondant:

#### Procédure

``` /yaml
kind: Deployment
spec:
  template:
    spec:
      image: abesesr/clamscan-docker:1.4.7
...
```

#### Vérification

La résolution du nom de l\'image ne change pas et reste la référence
longue

``` /bash
oc get deploy abesesr-web-clamav -o json |jq -r '.spec.template.spec.containers[0].image'
abesesr/clamscan-docker:1.4.7
```

#### Registry interne à OKD

#### Résultat désiré

C\'est la méthode la plus directe puisqu\'elle fait appel au registry
interne d\'Openshift par le nom du service. On décide donc d\'appeler le
repository comme on le ferait avec `docker.io` avec la structure
**\<registry\>/\<namespace\>/image_name:tag**

``` /bash
oc get svc -n openshift-image-registry
image-registry            ClusterIP   172.30.183.182   <none>        5000/TCP    651d
```

Pour rappel on peut faire appel à un service entre pods par la syntaxe
**\<service_name\>.\<namespace\>.svc**.

Le nom du service du registry interne d\'Openshift est donc
`image-registry.openshift-image-registry.svc:5000`

#### Procédure

``` /yaml
kind: Deployment
spec:
  template:
    spec:
      image: image-registry.openshift-image-registry.svc:5000/abesstp-nfs-build-beta2/abesstp-web:php-5.6.40-apache
...
```

#### Vérification

La résolution du nom de l\'image ne change pas et reste la référence
longue

``` /bash
oc get deploy abesesr-web-clamav -o json |jq -r '.spec.template.spec.containers[0].image'
image-registry.openshift-image-registry.svc:5000/abesstp-nfs-build-beta2/abesstp-web:php-5.6.40-apache
```

## imageStream

### Installation

Le flag `--scheduled` permet la comparaison de l\'image avec le registry
distant toutes les 15 minutes.

``` /bash
oc create is abesstp-web-clamav (--scheduled)
oc tag docker.io/abesesr/clamscan-docker:1.4.7 abesstp-nfs-build-beta2/abesstp-web-clamav:1.4.7
```

### Vérification

Ce n\'est pas le tout de créer des `imageStream`, il faut aussi
s\'assurer que les tags résolvent bien le registry cible. On s\'en
assure quand le tag produit une ressource `istag` contenant une hash
`sha256`.

``` /bash
oc get istag
abesstp-web-clamav:1.4.7 docker.io/abesesr/clamscan-docker@sha256:ab65daf8ad67b05e52edf153a8a9c8c52329eed5e84c9bfa7609bf290965d7c5
```

## Utilisation d\'imageStream dans la resource Deployment

**2 cas de figure** Les 2 cas traitent de la façon de résoudre ou non
les noms de l\'image à utiliser par la ressource `deployment`

### Résolution du nom de l\'image depuis un deployment

#### Résultat désiré

``` /yaml
kind: Deployment
spec:
  replicas: 1
  template:
    metadata:
      annotations:
        alpha.image.policy.openshift.io/resolve-names: '*'
...
```

Ainsi les déploiements peuvent directement utiliser le nom de
l`'imageStream` dans le champs image du deployment.

#### Procédure

``` /bash
oc set image-lookup deploy/<deployment_name>
oc set image-lookup deploy/abesstp-web-clamav (--enabled=true)
```

On peut ainsi directement utiliser le nom de l`'imagesStream` à la place
du nom du repository dans le `deployment`.

``` /bash
oc get deploy abesstp-web -o yaml
...
 image: abesstp-web-clamav:1.4.7
...
```

### Résolution du nom de l\'image depuis l\'imageStream

#### Résultat désiré

``` /yaml
kind: ImageStream
...
spec:
  lookupPolicy:
    local: true
...
```

De la même façon les déploiements peuvent maintenant directement
utiliser le nom de l`'imageStream` dans le champs image du deployment.

#### Procédure

``` /bash
oc set image-lookup <imageStream_name>
oc set image-lookup abesstp-web-clamav (--enabled=true)
oc set image-lookup imagestream --list
```

``` /bash
oc get deploy abesstp-web -o yaml
...
 image: abesstp-web-clamav:1.4.7
...
```

### Vérification

Le champ `image` du `deployment` change et fait bien référence à un hash
de l\'image, qui est une référence à l\'imageStream à la place de la
forme `imagestream_name:tag` que nous avions initialement configuré.

``` /bash
oc get deploy abesstp-web-clamav -o json |jq -r '.spec.template.spec.containers[0].image'
docker.io/abesesr/clamscan-docker@sha256:ab65daf8ad67b05e52edf153a8a9c8c52329eed5e84c9bfa7609bf290965d7c5
```

On peut aussi vérifier que l\'ensemble des `deployments` pointe bien
vers un hash représentant l\'imageStream.

``` /bash
for i in $(oc get deploy -o json | jq -r '.items[].metadata.name'); do echo "$i: $(oc get deploy $i -o json |jq -r '.spec.template.spec.containers[0].image')"; done
#ou bien simplement
oc get deploy -o json |jq -r '.items[].spec.template.spec.containers[0].image'
image-registry.openshift-image-registry.svc:5000/abesstp-nfs-build-demo/abesstp-db:5.5.62
image-registry.openshift-image-registry.svc:5000/abesstp-nfs-build-demo/abesstp-db-dumper:1.2.0
image-registry.openshift-image-registry.svc:5000/abesstp-nfs-build-demo/abesstp-web@sha256:6b004854e7967365a40cddd549383f77f0a5ac86f467663e0c42737e0612e4da
image-registry.openshift-image-registry.svc:5000/abesstp-nfs-build-demo/abesstp-web-clamav:1.4.7
image-registry.openshift-image-registry.svc:5000/abesstp-nfs-build-demo/abesstp-web-cron@sha256:0dae2a17678aa9a31dae15f84f41f7fedabe4e9b00c49df1959e22735d03cf45
```
