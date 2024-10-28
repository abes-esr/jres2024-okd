# Import d\'une image de container sous OKD4

Le but de la manœuvre est d\'importer une image docker ou podman
pré-existante dans le registry interne de OKD pour pouvoir ensuite
l\'exploiter.

## Depuis une source externe à OKD

<https://docs.openshift.com/container-platform/4.13/registry/accessing-the-registry.html>
Le but c\'est de se connecter depuis une source qui n\'a pas accès au
port 5000 du registry d\'OKD de l\'hôte
`default-route-openshift-image-registry.apps.v212.abes.fr`

-   On se logue côté `oc` dans le projet dans lequel on veut importer
    l\'image.

Attention, `oc login` (et non `export KUBECONFIG`) est la seule méthode
d\'authentification qui permette d\'obtenir un login et ainsi par la
suite d\'utiliser ce login pour connecter podman à un registre (la
méthode par mot de passe ne fonctionnera pas).

      oc login -u <user> -n <project>
      oc whoami -t
    sha256~X

-   Si on n\'a pas les droits `cluster-admin`, alors il faut
    s\'attribuer des droits. Si on ne précise pas le projet, alors les
    droits sont donnés pour le projet en cours.

      oc policy add-role-to-user registry-viewer <user> -n <project>
      oc policy add-role-to-user registry-editor <user> -n <project>
      oc describe rolebinding.rbac -n openshift-config

-   Pour attribuer ces mêmes droits pour l\'ensemble des projets, alors
    il faut utiliser

      oc policy add-cluster-role-to-user registry-viewer <project>
      oc policy add-cluster-role-to-user registry-editor <project>
      oc describe clusterrolebinding.rbac -n openshift-config

\* Par défaut, la route qui permet de consulter le registry depuis
l\'extérieur n\'est pas active.
<https://docs.openshift.com/container-platform/4.13/registry/securing-exposing-registry.html>
Il faut donc l\'activer:

``` bash
oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
```

-   La route qui expose le registry se trouve ainsi (3 façons
    d\'extraire le l\'url d\'accès au registry
    `default-route-openshift-image-registry.apps.v212.abes.fr`)

``` bash
HOST=$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}')
HOST=$(oc get route default-route -n openshift-image-registry -ojsonpath={.spec.host})
HOST=$(oc get route default-route -n openshift-image-registry -o json | jq -r .spec.host)
```

-   importer une image dans le registry de podman

``` bash
podman pull alpine
podman images
```

-   par défaut `podman` va chercher les images dans les registry
    prédéfinis dans `/etc/containers/registries.conf` dans cet ordre:

1.  registry.access.redhat.com
2.  registry.redhat.io
3.  docker.io

Il est tout à fait possible d\'en changer l\'ordre ou de rajouter un
registry

-   Connexion de podman au registry sans TLS

``` bash
podman login -u $(oc whoami) -p $(oc whoami -t) --tls-verify=false $HOST 
```

-   Connexion de podman au registry avec TLS

``` bash
mkdir -p /etc/containers/certs.d/${HOST}
oc get secret -n openshift-ingress  router-certs-default -o go-template='{{index .data "tls.crt"}}' | base64 -d | sudo tee /etc/containers/certs.d/${HOST}/${HOST}.crt  > /dev/null
podman login -u $(oc whoami) -p $(oc whoami -t) $HOST
```

-   On définit un tag où on va entreposer l\'image dans le registry
    distant

``` bash
podman tag docker.io/library/alpine $HOST/openshift/image3
```

-   Il ne reste qu\'à pousser l\'image dans ce tag

``` bash
podman push (--log-level=debug) $HOST/openshift/image3 (--tls-verify=false)
```

L\'image est disponible en tant qu\'image stream dans le projet
d\'origine de connexion d\'oc.

    oc get is -n <project>

Pour lister l\'ensemble des images disponibles sur le cluster

    oc get is --all-namespaces

## Depuis un container OKD

Le port 5000 du registry est disponible sur l\'hôte
`image-registry.openshift-image-registry.svc` On liste les noeuds
disponibles

    oc get nodes

On lance le mode debug du container voulu

    oc debug nodes/v212-t4k2k-worker-0-dgjzp

On rentre dans le chroot du container

``` bash
chroot /host
```

import des paramètres openshift de connexion quand ils existent

    export KUBECONFIG=/root/auth/kubeconfig

login à l\'api openshift

    oc login --token='' https://api.v212.abes.fr:6443 -n <project_name>

login au registry d\'openshift

    podman login -u kubeadmin -p $(oc whoami -t) image-registry.openshift-image-registry.svc:5000 --tls-verify=false

tag d\'une image, à toujours faire avant de la pusher

    podman tag docker.io/library/alpine image-registry.openshift-image-registry.svc:5000/openshift/image

push de l\'image dans le registry

    podman push image-registry.openshift-image-registry.svc:5000/openshift/image --tls-verify=false

On peut importer des images docker depuis n\'importe quel registry local
ou distant

    oc import-image openshift/image --from=docker.io/alpine --confirm
    oc import-image openshift/image --from=image-registry.openshift-image-registry.svc:5000/openshift/image --confirm

Par défaut, l\'import se fait avec le tag `latest`. Si on veut importer
une autre version de l\'image, il faut définir le tag de cette image
dans le repository:

``` bash
oc tag --source=docker docker.io/anapsix/alpine-java:8 alpine-java:8
oc import-image alpine-java:8 --from=docker.io/anapsix/alpine-java:8 --confirm
oc get is alpine-java
oc get istag | grep alpine-java
oc describe is/alpine-java
oc describe istag/alpine-java:8
```
