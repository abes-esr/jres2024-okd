# Build initial et CD sur Kubernetes

L\'objectif est de déployer un service `docker-compose.yml` avec la
directive `build`. Il en résultera la construction d \'une image par le
système local, avant d\'être poussée sur le registry du cluster
OpenShift. Il ne s\'agit pas donc à proprement parlé d\'une CI
puisqu\'une fois l\'image poussée il n\'y a pas de trigger git pour
déclencher la construction d\'une nouvelle image. Cela est fait de
manière traditionnelle avec des pipelines `Jenkins` ou `Tekton`.

Cependant, cela pourra être ajouté dans un second temps, le but premier
étant la création d\'une image permettant le portage immédiat de
l\'application dans Kubernetes.

En résumé, l\'intégration est initiale et non continue et elle se
déroule en 3 étapes:

-   Tag de l\'image
-   construction des images
-   push dans le registry

## Pré-requis

-   (optionnel) AUthentification à DockerHub pour pull des images
    nécessaires à la construction de l\'image (contourner le limit rate)

``` /bash
docker login -u dockerhubabes
```

-   Récupération du token du cluster Openshift:

``` /bash
TOKEN=$(oc whoami -t)
#ou bien avec curl
export USER=kubeadmin
export PASSWD=**CHANGED**
export ENDPOINT=oauth-openshift.apps.orchidee.okd-dev.abes.fr
export TOKEN=$(curl -s -u $USER:$PASSWD -kI "https://$ENDPOINT/oauth/authorize?client_id=openshift-challenging-client&response_type=token" | grep -oP "access_token=\K[^&]*")
```

-   Authentification au registry distant pour push de l\'image
    construite sur le registry local (voir
    [registry_d\_images](/okd/registry_d_images))

``` /bash
docker --tlscacert /etc/docker/certs.d/default-route-openshift-image-registry.apps.orchidee.okd-dev.abes.fr.crt login -u kubeadmin -p $TOKEN default-route-openshift-image-registry.apps.orchidee.okd-dev.abes.fr
```

-   Récupération de l\'environnement de build

``` /bash
git clone -b patch-1 https://github.com/natman/abesstp-docker.git
cd abesstp-docker
```

-   Récupération des sous modules git

``` /bash
git submodule update --init --recursive
```

## CI

Il s\'agit de la construction et du push de l\'image dans un registry.

### Build Kompose

Kompose permet de construire des images localement avant de les pousser
dans un registry.

Il existe deux méthodes, locale et custom:

-   LOCAL BUILD

``` /bash
docker-compose config | kompose -f - convert --build local --push-image --push-image-registry default-route-openshift-image-registry.apps.orchidee.okd-dev.abes.fr
```

Cette méthode peut sembler facile à appliquer, cependant elle rencontre
des limitations dans certains cas de figure:

1.  erreur quand des liens dynamiques existent dans le contexte de
    construction d\'images
2.  impose la libraries d\'images \"library\" de dockerhub, ne permet
    pas la personnalisation quand on veut pousser les images dans un
    registry autre que DockerHub.

-   CUSTOM BUILD (avec docker local)

``` /bash
docker-compose config | ./kompose -f - convert --build-command 'docker build -t abesstp-web:php-5.6.40-apache images/abesstp-web/' --push-command 'docker push default-route-openshift-image-registry.apps.orchidee.okd-dev.abes.fr/abesstp-nfs/abesstp-web:php-5.6.40-apache'
```

1.  limitation à un build/push par commande
2.  option présente avec la dernière version de kompose (1.34)

### Build Manuel

-   build de l\'image

``` /bash
docker build -t abesstp-web:php-5.6.40-apache images/abesstp-web/
```

-   tag de l\'image

``` /bash
docker tag abesstp-web:php-5.6.40-apache default-route-openshift-image-registry.apps.orchidee.okd-dev.abes.fr/abesstp-nfs/abesstp-web:php-5.6.40-apache
```

-   push de l\'image

``` /bash
docker push default-route-openshift-image-registry.apps.orchidee.okd-dev.abes.fr/abesstp-nfs/abesstp-web:php-5.6.40-apache
```

## CD

Dans notre configuration actuelle, c\'est `Keel` qui compare et déploie
les versions d\'images à la manière de `Watchtower` pour Docker.

Si on veut déclencher (trigger) le déploiement automatique avec la
resource `deployment` de k8s à la place de `deploymentConfig` avec
Openshift, il faut paramétrer les déploiements pour qu\'ils utilisent
l\'API `imageStream` d\'Openshift:
(<https://docs.okd.io/latest/openshift_images/using-imagestreams-with-kube-resources.html>)

-   en rendant l\'imageStream disponible pour les déploiements

<https://docs.openshift.com/container-platform/4.8/openshift_images/using-imagestreams-with-kube-resources.html>

``` /bash
oc set image-lookup abesstp-web --enabled=true
```

-   en permettant à un `deployment` d\'utiliser les ressources
    `imageStream` disponibles pour le namespace:

``` /bash
oc set image-lookup deploy/abesstp-web
```

On peut ainsi créer l `imageStream` avec la mise à disposition de l\'api
pour tous les deployments

``` /bash
oc create is abesstp-web --lookup-local=true
```

Il reste enfin à déclencher le déploiement de l\'image

<https://docs.openshift.com/container-platform/4.8/openshift_images/triggering-updates-on-imagestream-changes.html>

``` /bash
oc set triggers deploy/abesstp-web --from-image=abesstp-web:php-5.6.40-apache -c abesstp-web
```

On vérifie que l\'image est bien disponible dans le registry interne:

``` /bash
oc get images| grep image-registry.openshift-image-registry.svc:5000
oc describe images sha256:1cfb09aa043a3c4d24baa984879d16decc7be038501f35465c0be59dd95c44bb
```
