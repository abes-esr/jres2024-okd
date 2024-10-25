## Redéploiement d\'un cluster operator

Les **cluster operators** sont les services kubernetes essentiels au
fonctionnement du cluster OKD. Ils se déploient également sous la forme
de pods tournant exclusivement sur les masters.

``` /bash
oc get co

NAME                                       VERSION                          AVAILABLE   PROGRESSING   DEGRADED   SINCE   MESSAGE
authentication                             4.12.0-0.okd-2023-04-01-051724   True        False         False      4d7h    
baremetal                                  4.12.0-0.okd-2023-04-01-051724   True        False         False      75d     
cloud-controller-manager                   4.12.0-0.okd-2023-04-01-051724   True        False         False      75d     
cloud-credential                           4.12.0-0.okd-2023-04-01-051724   True        False         False      75d     
cluster-autoscaler                         4.12.0-0.okd-2023-04-01-051724   True        False         False      75d     
config-operator                            4.12.0-0.okd-2023-04-01-051724   True        False         False      75d     
console                                    4.12.0-0.okd-2023-04-01-051724   True        False         False      4d7h    
control-plane-machine-set                  4.12.0-0.okd-2023-04-01-051724   True        False         False      75d     
csi-snapshot-controller                    4.12.0-0.okd-2023-04-01-051724   True        False         False      14d     
dns                                        4.12.0-0.okd-2023-04-01-051724   True        False         False      75d     
etcd                                       4.12.0-0.okd-2023-04-01-051724   True        False         False      15d     
image-registry                             4.12.0-0.okd-2023-04-01-051724   True        False         False      4d20h   
ingress                                    4.12.0-0.okd-2023-04-01-051724   True        False         False      6d8h    
insights                                   4.12.0-0.okd-2023-04-01-051724   True        False         False      75d     
kube-apiserver                             4.12.0-0.okd-2023-04-01-051724   True        False         False      75d     
kube-controller-manager                    4.12.0-0.okd-2023-04-01-051724   True        False         False      75d     
kube-scheduler                             4.12.0-0.okd-2023-04-01-051724   True        False         False      75d     
kube-storage-version-migrator              4.12.0-0.okd-2023-04-01-051724   True        False         False      4d8h    
machine-api                                4.12.0-0.okd-2023-04-01-051724   True        False         False      75d     
machine-approver                           4.12.0-0.okd-2023-04-01-051724   True        False         False      75d     
machine-config                             4.12.0-0.okd-2023-04-01-051724   True        False         False      4d8h    
marketplace                                4.12.0-0.okd-2023-04-01-051724   True        False         False      75d     
monitoring                                 4.12.0-0.okd-2023-04-01-051724   True        False         False      11d     
network                                    4.12.0-0.okd-2023-04-01-051724   True        False         False      75d     
node-tuning                                4.12.0-0.okd-2023-04-01-051724   True        False         False      5d      
openshift-apiserver                        4.12.0-0.okd-2023-04-01-051724   True        False         False      4d7h    
openshift-controller-manager               4.12.0-0.okd-2023-04-01-051724   True        False         False      75d     
openshift-samples                          4.12.0-0.okd-2023-04-01-051724   True        False         False      5d      
operator-lifecycle-manager                 4.12.0-0.okd-2023-04-01-051724   True        False         False      75d     
operator-lifecycle-manager-catalog         4.12.0-0.okd-2023-04-01-051724   True        False         False      75d     
operator-lifecycle-manager-packageserver   4.12.0-0.okd-2023-04-01-051724   True        False         False      14d     
service-ca                                 4.12.0-0.okd-2023-04-01-051724   True        False         False      75d     
storage                                    4.12.0-0.okd-2023-04-01-051724   True        False         False      14d 
```

Les deux opérateurs qui peuvent poser le plus de problèmes sont `etcd`
et `kube-apiserver`.

Le namespace dans lequel ils évoluent est de la forme
**openshift-\<cluster operator\>**

Voici la marche à suivre pour les relancer:

``` /bash
NAMESPACE=openshift-etcd
oc get co etcd
oc get co etcd -o json | jq -r '.status.conditions[] | select(.type =="Degraded")'
# désactivation du quorum pour remplacement d'un noeud etcd 
# oc patch etcd/cluster --type=merge -p '{"spec": {"unsupportedConfigOverrides": {"useUnsupportedUnsafeNonHANonProductionUnstableEtcd": true}}}'
oc patch etcd/cluster --type=merge -p '{"spec": {"unsupportedConfigOverrides": null}}'
oc get pods -n $NAMESPACE
for i in $(oc get -n $NAMESPACE pods | grep 'Error\|Completed\|retry' | cut -d' ' -f1); do echo $i; oc delete -n $NAMESPACE pods $i; done
oc patch etcd/cluster --type merge -p "{\"spec\":{\"forceRedeploymentReason\":\"Forcing new revision with random number $RANDOM to make message unique\"}}"
oc get co
```

``` /bash
NAMESPACE=openshift-kube-apiserver
oc get co kube-apiserver
oc get co kube-apiserver -o json | jq -r '.status.conditions[] | select(.type =="Degraded")'
# désactivation du quorum pour remplacement d'un noeud etcd 
# oc patch kubeapiserver/cluster --type=merge -p '{"spec": {"unsupportedConfigOverrides": {"useUnsupportedUnsafeNonHANonProductionUnstableEtcd": true}}}'
oc patch kubeapiserver/cluster --type=merge -p '{"spec": {"unsupportedConfigOverrides": null}}'
oc get pods -n $NAMESPACE
for i in $(oc get -n $NAMESPACE pods | grep 'Error\|Completed\|retry' | cut -d' ' -f1); do echo $i; oc delete -n $NAMESPACE pods $i; done
oc patch kubeapiserver/cluster --type merge -p "{\"spec\":{\"forceRedeploymentReason\":\"Forcing new revision with random number $RANDOM to make message unique\"}}"
oc get co
```
