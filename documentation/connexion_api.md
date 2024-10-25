# Connexion à OKD 4

### Fichier de log par défaut

Les informations d\'installation et de connexion générées par
l\'installateur se situent dans le fichier de log:

    time="2021-03-11T08:12:35+01:00" level=info msg="Install complete!"
    time="2021-03-11T08:12:35+01:00" level=info msg="To access the cluster as the system:admin user when using 'oc', run 'export KUBECONFIG=/root/auth/kubeconfig'"
    time="2021-03-11T08:12:35+01:00" level=info msg="Access the OpenShift web-console here: https://console-openshift-console.apps.v212.abes.fr"
    time="2021-03-11T08:12:35+01:00" level=info msg="Login to the console with user: \"kubeadmin\", and password: \"my_password\""
    time="2021-03-11T08:12:35+01:00" level=debug msg="Time elapsed per stage:"
    time="2021-03-11T08:12:35+01:00" level=debug msg="    Infrastructure: 5m16s"
    time="2021-03-11T08:12:35+01:00" level=debug msg="Bootstrap Complete: 16m7s"
    time="2021-03-11T08:12:35+01:00" level=debug msg="               API: 1m52s"
    time="2021-03-11T08:12:35+01:00" level=debug msg=" Bootstrap Destroy: 37s"
    time="2021-03-11T08:12:35+01:00" level=debug msg=" Cluster Operators: 18m34s"
    time="2021-03-11T08:12:35+01:00" level=info msg="Time elapsed: 41m58s"

L\'utilisateur `kubeadmin` est un utilisateur d\'administration
temporaire qui possède tous les droits. Une fois les utilisateurs
configurés, il faudra le supprimer telle que l\'interface nous le
propose. (voir - [](/okd/création d'un utilisateur))

On se connecte donc à la console web
<https://console-openshift-console.apps.v212.abes.fr> avec ces
identifiants par défaut.

Pour \"OKD-Prod\" (et le projet guacamole) :
<https://console-openshift-console.apps.orchidee.okd-prod.abes.fr/k8s/ns/guacamole/deployments>

Pour se connecter à l\'API avec le client `oc`, il faut d\'abord
importer le fichier `kubeconfig` généré par l\'installateur, qui
contient l\'ensemble des éléments nécessaires à la connexion (url,
utilisateur, certificats, \...) Ce fichier contient également un token
qui a été généré par l\'installateur.

    export KUBECONFIG=/root/auth/kubeconfig
    oc login

** !!!ATTENTION!!!** Le token utilisé n\'étant valide qu\'un laps de
temps, kubeconfig ne suffira plus par la suite à se connecter sans
authentification. Il faudra alors demander un nouveau token à
l\'adresse:
<https://oauth-openshift.apps.v212.abes.fr/oauth/token/request> où on
s'authentifie en web avec l\'utilisateur voulu le token généré est
propre à cet utilisateur et permettra uniquement de se connecter sous
les droits de cet utilisateur.

Si cette étape est omise, on pourra quand même se connecter mais avec
des paramètres manuels à rajouter à la ligne de commande

    oc login -u kubeadmin https://api.v212.abes.fr:6443 
    oc login --token=sha256~token https://api.v212.abes.fr:6443

On vérifie qu\'on est bien sous l\'utilisateur voulu avec la commande

    oc whoami

On peut afficher le token en cours de validité de cet utilisateur:

    oc whoami -t

Par défaut on se retrouve dans le projet `default`, mais on peut changer
de projet ainsi

    oc project <new_project>

On peut changer à tout moment d\'utilisateur avec

    oc login -u <user> b -n <project>

ou se déconnecter avec

    oc logout

### Modification de l\'expiration du token

<https://docs.okd.io/latest/authentication/configuring-internal-oauth.html>

Un token est valable 24 heures par défaut. Pour modifier cette valeur,
deux façons:

    oc edit oauth.config.openshift.io/cluster
    oc edit oauth cluster

ou

    apiVersion: config.openshift.io/v1
    kind: OAuth
    metadata:
      name: cluster
    spec:
      tokenConfig:
        accessTokenMaxAgeSeconds: 172800 

    oc apply -f </path/to/file.yaml>

### Modification du timeout du token

    oc edit oauth cluster

    apiVersion: config.openshift.io/v1
    kind: OAuth
    metadata:
    ...
    spec:
      tokenConfig:
        accessTokenInactivityTimeout: 400s 

Vérifier que les pods du serveur d\'OAuth ont bien redémarré

    oc get clusteroperators authentication
