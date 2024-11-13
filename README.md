# Scripts de conversion Docker vers Kubernetes


## Contexte initial

Le but initial de ce repo était de rassembler différents scripts bash, python, ansible visant à normaliser et convertir un fichier docker-compose.yml en manifests k8s avec différentes options telles que la gestion des env_file et des secrets. 

Ces scripts ont été développés dans le cadre d'un POC piloté par le Service Infrastructure et Réseau, qui visait initialement à porter des applications professionnelles de l'Abes fonctionnant sous Docker vers Kubernetes sans régressions. OKD, le projet upstream d'Openshift, a été choisi comme distribution k8s.

## Jres 224
Le comité d'organisation des [Jres24](https://2024.jres.org/) (Rennes, 10-13 décembre 24) ayant validé notre proposition ["Vers la symphonie des conteneurs"](https://2024.jres.org/programme#modal-23), nous avons avons ajouté à ce repo l'ensemble des éléments qui ont été nécessaires à la conception de l'[article](documentation/article_jres24.md) et du [poster](documentation/files/poster-jres-2024.jpg).

Le script [compose2manifests.sh](compose2manifests.sh) a été complété pour répondre à un cas d'usage plus global, apportant des fonctionnalités supplémentaires telles que 
  * l'installation de pré-requis
  * la recherche automatiques des hôtes Docker
  * la vérification de la connectivité des hôtes 
  * l'installation des clés ssh
  * la recherche dynamiques des ports applicatifs
  * la copie de persistentVolumes
  * l'installation de drivers CSI
  * le traitement des PV en multi attachements
  * le calcul dynamique des taille des PV
  * le support des montages NFS
  * etc...

### Script Bash
Cette procédure ne nécessite qu'un simple fichier docker-compose.yml et du .env correspondant dans le répertoire courant. 
Il faut comme prérequis les paquets (la procédure est indépendante de l'OS)
- jq
```bash
sudo wget https://github.com/jqlang/jq/releases/latest/download/jq-linux-amd64 -O /usr/local/bin/jq &&  sudo  chmod +x /usr/bin/jq
```
- yq
```bash
sudo wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq &&  sudo  chmod +x /usr/bin/yq
```
- docker-compose
```bash
sudo wget https://github.com/docker/compose/releases/latest/download/docker-compose-linux-aarch64 -O /usr/local/bin/docker-compose &&  sudo  chmod +x /usr/bin/docker-compose
```
- kompose
```bash
sudo wget https://github.com/kubernetes/kompose/releases/latest/download/kompose-linux-amd64 -O /usr/local/bin/kompose &&  sudo  chmod +x /usr/bin/kompose
```
- moreutils
```bash
yum install moreutils -y 
apt install moreutils -y
```

Ensuite il suffit d'exécuter simplement:
```bash
chmod +x compose2manifests.sh
./compose2manifests.sh 
```

pour obtenir les manifests k8s correspondant: deployment et services.

Pour déployer l'appli dans OKD/k8s:
```bash
export KUBECONFIG=~/orchidee_install/auth/kubeconfig
oc apply -f "*.yaml"
oc get all

```
#### Options du script

```bash
./compose2manifests.sh [ prod || test || dev || local ] [ appli_name ] [default || '' || secret || env_file | help] [kompose] [helm]

```

- **$1** dev|test|prod: environnement sur lequel récupérer le .env. Local: fournir manuellement les '.env' et 'docker-compose.yml'

- **$2** appli_name: nom de l'application à convertir

- **$3** default or '' : Generates cleaned appli.yml compose file to plain k8s manifests

- **$4** env_file: Generates cleaned advanced appli.yml with migrating plain 'environment' to 'env_file' statement, will be converted into k8s configmaps"

- **$5** secret: The same as env_file, in addition generates advanced appli.yml with migrating all vars containing 'PASSWORD' or 'KEY' as keyword to secret,will be converted into k8s secrets"

- **$6** kompose: Converts appli.yml into plain k8s manifests ready to be deployed with 'kubectl apply -f *.yaml

- **$7** helm: Kompose option that generates k8s manifest into helm skeleton for appli.yml

- exemples
```bash
./compose2manifests.sh prod item secret kompose helm
./compose2manifests.sh local qualimarc secret kompose helm
```
