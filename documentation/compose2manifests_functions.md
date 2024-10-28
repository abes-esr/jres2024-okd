## compose2manifests.sh

`\> compose2manifests.sh environnement appli env_file kompose`

### environnement appli

-   vérification et si besoin installation des pré-requis : jq, yq, jc,
    docker-compose, kompose, oc, kubectl

-   détermination du domaine

-   recherche automatique de l'hôte Docker de l'application définie ou
    saisie manuelle des hôtes Docker

-   vérification de la connectivité ssh aux hôte Docker par clé, le cas
    échéant génération et installation d'une clé publique.

-   téléchargement du « docker-compose.yml » par Github ou depuis l'hôte
    Docker

-   téléchargement du « .env » depuis l'hôte Docker

-   personnalisation de la variable .env

-   remplacement du nom du service par la directive « container_name »

### env_file

#### Transformation des variables en env_file

-   L'objectif de la transformation de la directive `environment` en `env_file` est de faciliter la prise en charge de `Kompose` pour une conversion de type `secretMapKeyRef` et `configMapKeyRef`. Cet objet `env` défini dans l'api `deployment` ne doit pas contenir de caractère `_` et être en minuscule.

-   analyse les variables du fichier .env pour distinguer les variables
    sensibles qui seront ensuite converties par kompose en objet k8s
    « secret », des variables non sensibles qui seront transformées en
    objet « configMap ».

### kompose

#### Traitement des yaml générés

##### Correction des bugs kompose

-   `patch_RWO ()`

    Kompose transforme la directive docker ReadOnly d'un volume en
    volume ReadOnlyMany qui n'est pas supporté par la plupart des
    drivers CSI. Le patch transforme ReadOnlyMany en ReadWriteOnly

-   `patch_secret ()`

    Lors de la création d'un secret, le caractère « \\n » est inséré en
    base64, le patch le corrige

-   `patch_secretKeys ()`

    les références à un secretKey doivent être faite en minuscule et sans caractère `.` ou `_ `. L'importation depuis Docker peut
    faire référence à des noms en majuscule ou à des combinaisons de caractères non acceptés par les RFC adoptées par k8s.

-   `patch_labels ()`

    Contourne la limitation à 64 caractères des labels et des noms de volumes

##### Réseau

-   `patch_expose_auto ()`

    Analyse les ports déclarés dans le docker-compose et les compare à ceux actifs sur le Docker host. Les ports existants et non déclarés dans le docker-compose.yml sont ajoutés dans leurs services respectifs.

-   `patch_expose ()`

    permet de rajouter manuellement des ports aux services existants.

-   `patch_networkPolicy ()`

    Traite l'ingress pour rendre l'appli disponible depuis l'extérieur

##### Stockage

-   `create_pv2 ()`

    Ce patch cherche les volumes NFS montés sur l'hôte docker source et
    crée un persistent Volume de type NFS plutôt que csi, avec les mêmes
    caractéristiques.

-   `create_pvc_nfs ()`

    Transforme le fichier pvc convertit par kompose en claim du
    persistent volume généré avec create_pv2 ()

-   `create_sc ()`

    Certains containers Docker accèdent au même volume. Beaucoup de
    drivers csi ne supportant que le mode ReadWriteOnly, ce patch
    propose d'installer le drivers officiel nfs.csi.k8s.io avec la
    capacité RWX et de convertir ces volumes en pvc compatibles.

##### Fichiers

-   `patch_configmaps ()`

    Transforme les fichiers de configuration de type volume en
    configMaps de quelques ko à la place d'un pvc de 100Mo. Rejoint les bonnes pratiques k8s

-   `create_configmaps ()`

    Crée des objets configMaps pour les volumes bind qui sont des
    fichiers et non des répertoires. Un montage sshfs est utilisé sur l'hôte docker pour utiliser facilement la commande « oc create cm ». On peut ainsi créer des configmaps d'objets binaires.

#### Déploiement de l'application

-   Création du projet.

-   Génération d'une règle Security Context Constraint pour le
    ServiceAccount par défaut. Sans cela les conteneurs root ne
    démarrent pas sous OKD.

-   Création du secret Docker pour récupérer des images sur DockerHub sans restriction.

#### Copie des données persistantes

-   `select_nfs_mount_point ()`

    Tri des pvc NFS et claim pour éviter par la suite la copie inutile
    des partages NFS.

-   `copy_to_okd ()`

    Cherche sur l'hôte Docker la taille des répertoires des volumes
    persistants pour les inclure dans les pvc générés par kompose (par défaut 100Mio). Copie au travers d'un copier-coller et volume après volume les données via un container de debug qui se connecte en SSH.

#### Actions finales

-   Redémarrage des pods

-   Exposition des services pour créer une route

-   Génération de l'URL d'accès à l'application.
