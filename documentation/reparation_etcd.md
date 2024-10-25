# Réparation d\'un noeud etcd

## Contexte

`etcd` est le `cluster operator` tournant sur les masters qui gère la
cohérence du cluster OKD. C\'est le premier élément qu\'il faut regarder
lors d\'un dysfonctionnement d\'un noeud master. La procédure à suivre
est différente suivant qu\'on cherche à remplacer un master etcd ou bien
ajouter/réparer un noeud.

## Remplacement d\'un master etcd

<https://docs.okd.io/latest/backup_and_restore/control_plane_backup_and_restore/replacing-unhealthy-etcd-member.html#restore-replace-stopped-etcd-member_replacing-unhealthy-etcd-member>

## Ajout/Réparation d\'un master etcd

-   Lister les opérateurs qui ne fonctionnent pas correctement

``` /bash
oc get co
```

-   Trouver les logs qui en disent plus sur l\'opérateur (ici etcd)

``` /bash
oc describe co etcd
```

-   Trouver les logs qui en disent plus sur le cluster (ici etcd)

Etat du cluster

``` /bash
oc get etcd/cluster -oyaml
```

-   Repérer le pod chargé de l\'installation de l\'opérateur
    (\"openshift-\<operator\>\")

``` /bash
oc get -n "openshift-etcd" pods
```

Il y a 4 types de pods: **guard, operator, installer, revision-pruner**.
Celui qui nous intéresse est l\'**installer** qui doit être en mode
\'completed\'. S\'il ne l\'est pas, il se peut qui\'il soit en mode
**retry** C\'est dans les logs de ce pod qu\'il faut chercher les
raisons our lesquelles il n\'installe pas l\'operator.

-   Trouver les logs associés de la raison de la non installation
    (manque de resources par ex):

``` /bash
oc describe -n "openshift-etcd" pods "installer-10-retry-7-orchidee-ccbm8-master-30"
oc get -oyaml -n "openshift-etcd" pods "installer-10-retry-7-orchidee-ccbm8-master-30"
```

Dans notre cas, on tombe sur une erreur de rsource dans la partie
\'Events\':

``` /bash
Warning  UnexpectedAdmissionError  104m  kubelet, crawford-libvirt-xqscg-master-0  Unexpected error while attempting to recover from admission failure: preemption: \ 
error finding a set of pods to preempt: no set of running pods found to reclaim resources: [(res: memory, q: 11067392), ]
```

-   On efface les pods en échec

``` /bash
NAMESPACE=openshift-etcd; for i in $(oc get -n $NAMESPACE pods | grep 'Error\|Completed\|retry' | cut -d' ' -f1); do echo $i; oc delete -n $NAMESPACE pods $i; done
```

-   Une fois que la correction est apportée, le redémarrage du pod se
    fait en principe tout seul. Si ce n\'est pas le cas, on peut forcer
    sa recréation en le supprimant:

``` /bash
oc delete pod/etcd-orchidee-7cn9g-master-20"
```

## Redéploiement d\'un cluster operator

Il peut suffire dans certains cas où le status du cluster operator est
bloqué de le redémarrer.

[Redéploiement d\'un cluster operator](redeploiement_cluster_operator.md)
