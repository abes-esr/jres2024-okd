# okd



## Getting started

Le but de ce repo est de rassembler différents scripts bash, python, ansible visant à normaliser et convertir un fichier docker-compose.yml en manifests k8s avec différentes options telles que la gestion des env_file et des secrets.

Cette procédure ne nécessite qu'un simple fichier docker-compose.yml et du .env correspondant dans le répertoire courant. 
Il faut comme prérequis les paquets jq, yq, moreutils, docker-compose, kompose

Ensuite il suffit d'exécuter simplement:
```
./compose2manifests.sh 
```

pour obtenir les manifests k8s correspondant: deployment et services.

Pour déployer l'appli dans OKD/k8s:
```
export KUBECONFIG=~/orchidee_install/auth/kubeconfig
oc apply -f "*.yaml"
oc get all

```
## Options du script

```
./compose2manifests.sh [ prod || test || dev || local ] [ appli_name ] [default || '' || secret || env_file | help] [kompose] [helm]"

```

1. dev|test|prod: environnement sur lequel récupérer le .env. Local: fournir manuellement les '.env' et 'docker-compose.yml'

2. appli_name: nom de l'application à convertir

3. default or '' : Generates cleaned appli.yml compose file to plain k8s manifests

4. env_file: Generates cleaned advanced appli.yml with migrating plain 'environment' to 'env_file' statement, will be converted into k8s configmaps"

5. secret: The same as env_file, in addition generates advanced appli.yml with migrating all vars containing 'PASSWORD' or 'KEY' as keyword to secret,will be converted into k8s secrets"

6. kompose: Converts appli.yml into plain k8s manifests ready to be deployed with 'kubectl apply -f *.yaml"

7. helm: Kompose option that generates k8s manifest into helm skeleton for appli.yml"

8. exemples
```
./compose2manifests.sh secret kompose helm"
./compose2manifests.sh diplotaxis1 qualimarc secret kompose helm ./compose2manifests.sh local qualimarc secret kompose helm"
```
