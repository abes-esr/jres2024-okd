# Création d\'utilisateurs OKD 4

L\'installation d\'OKD fournit un utilisateur par défaut `kubeamin` qui
ne possède pas tous les droits mais qui permet de créer des utilisateurs
avec des droits. Cet utilisateur doit rester temporaire et doit être
détruit une fois que les comptes admin ont été créés et validés.

## IDPs

<https://docs.openshift.com/container-platform/4.7/authentication/understanding-identity-provider.html>

Parmi la liste des Identity Providers qui permettent de se connecter à
OKD, nous avons comme objectif final d\'utiliser le type LDAP sur Active
directory. Après plusieurs essais infructueux et dans un but
pragmatique, nous allons utiliser le provider Htpasswd qui est plus
simple à mettre en œuvre.

### AD

<https://docs.vmware.com/en/VMware-Validated-Design/6.0.1/sddc-deployment-of-a-red-hat-openshift-workload-domain-in-the-first-region/GUID-0E8821AC-7C60-4997-B8A5-AB3ED18DFB1D.html>

Créer un `secret` LDAP `ldap-bind-password-676wf`

``` bash
oc create secret generic ldap-bind-password-676wf --from-literal=bindPassword=levant_passwd -n openshift-config
```

#### Méthode d\'édition

Éditer l\'objet `Oauth` en mode vi pour rajouter un IDP

``` bash
oc edit oauth.config.openshift.io/cluster
oc edit oauth cluster
```

Ajouter l\'IDP sous la partie `spec`:

``` yaml
spec:
  identityProviders:
  - ldap:
      attributes:
        email:
        - mail
        id:
        - sAMAccountName
        name:
        - displayName
        preferredUsername:
        - sAMAccountName
      bindDN: CN=acces_ldap_okd,OU=applicatif,OU=Utilisateurs,DC=levant,DC=abes,DC=fr
      bindPassword:
        name: ldap-bind-password-676wf
      insecure: false
      url: ldaps://ldap-win.abes.fr/OU=personnels,OU=Utilisateurs,DC=levant,DC=abes,DC=fr?sAMAccountName?sub?
    mappingMethod: claim
    name: ldap-win
    type: LDAP
```

#### Méthode `Custom Resource`

Créer l\'objet yaml ldap_cr.yaml `OAuth`

``` yaml
apiVersion:config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - ldap:
      attributes:
        email:
        - mail
        id:
        - sAMAccountName
        name:
        - displayName
        preferredUsername:
        - sAMAccountName
      bindDN: CN=acces_ldap_okd,OU=applicatif,OU=Utilisateurs,DC=levant,DC=abes,DC=fr
      bindPassword:
        name: ldap-bind-password-676wf
      insecure: false
      url: ldaps://ldap-win.abes.fr/OU=personnels,OU=Utilisateurs,DC=levant,DC=abes,DC=fr?sAMAccountName?sub?
    mappingMethod: claim
    name: ldap-win
    type: LDAP
```

Il reste à appliquer la ressource au système

``` bash
oc apply -f ldap_cr.yaml 
```

### Htpassword

#### Création

<https://docs.openshift.com/container-platform/4.7/authentication/identity_providers/configuring-htpasswd-identity-provider.html>

Htpassword n\'est autre qu\'un fichier plat utilisé par apache pour
générer des mots de passes hashés. L\'utilisation est donc statique.

-   Installer htpasswd

``` bash
  yum install -y httpd-tools
```
-   créer un utilisateur

``` bash
  htpasswd -c -B -b  /tmp/users.htpasswd user1 <password>
```

-   On peut par la suite ajouter des utilisateurs sans l\'option de
    création `-c`

``` bash
  htpasswd  -B -b  /tmp/users.htpasswd user2 <password>
```

-   créer un objet `secret` OKD à partir de ce fichier dans le namespace
    openshift-config

``` bash
  oc create secret generic htpass-secret --from-file=htpasswd=users.htpasswd -n openshift-config
  oc get secrets -n openshift-config
```

-   créer un fichier `Custom Ressource` yaml

``` yaml
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: my_htpasswd_provider 
    mappingMethod: claim 
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpass-secret 
 
```

-   Appliquer la CR

``` bash
  oc apply -f </path/to/CR>
```

Ou directement éditer l\'objet cluster

``` bash
  oc edit oauth cluster
```

#### Ajout/Modification d\'un utilisateur

<https://docs.openshift.com/container-platform/4.7/authentication/identity_providers/configuring-htpasswd-identity-provider.html>

-   Récupérer le fichier htpassword hashé

``` bash
  oc get secret htpass-secret -ojsonpath={.data.htpasswd} -n openshift-config | base64 -d > users.htpasswd
```

-   Effectuer la mise à jour

``` bash
  htpasswd -D users.htpasswd <username>
  htpasswd  -Bb  /tmp/users.htpasswd user2 <password>
```

-   Remplacer le fichier htpassword existant

``` bash
  oc create secret generic htpass-secret --from-file=htpasswd=users.htpasswd --dry-run=client -o yaml -n openshift-config | oc replace -f -
```

-   Si suppression d\'un utilisateur

``` bash
  oc delete user <username>
  oc delete identity my_htpasswd_provider:<username>
```

-   vérifications

``` bash
  oc get users
  oc get identity
  oc get secrets -n openshift-config
```

-   On peut aussi directement éditer l\'objet Oauth en mode vi

``` bash
  oc edit oauth.config.openshift.io/cluster
  oc edit oauth cluster
```

#### Ajout de droits

<https://docs.openshift.com/container-platform/4.7/authentication/using-rbac.html>

-   devenir admin d\'un projet et l\'avoir à disposition au login

``` bash
  oc adm policy add-role-to-user admin <user> -n <project>
  oc describe rolebinding.rbac -n openshift-config
```

-   devenir administrateur global (pour remplacer kubeadmin)

``` bash
  oc adm policy add-cluster-role-to-user cluster-admin <user> --rolebinding-name=cluster-admin
  oc describe clusterrolebinding.rbac -n openshift-config
```

On peut désormais se connecter avec `oc` tel que décrit ici -
[](connexion_api)

Une fois qu\'on a validé que les utilisateurs créés ont les mêmes droits
que `kubeadmin` avec les droits `cluster-admin`, on peut effacer cet
utilisateur:

``` bash
  oc delete secrets kubeadmin -n kube-system
```
