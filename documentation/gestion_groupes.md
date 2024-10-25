# Gestion des groupes

## Gestion manuelle

On peut simplement créer des groupes manuellement

    oc adm groups new <group> <user>

Ajouter des utilisateurs à un groupe existant

     oc adm groups add-users <group> <user>
        

Retirer des utilisateurs

    oc adm groups remove-users <group> <user>

Retirer un groupe

    oc delete group <group>

Informations sur un group et ses utilisateurs

    oc get group <group>

## Import de groupe `Active Directory`

<https://docs.okd.io/latest/authentication/ldap-syncing.html>

On peut importer des groupe existants d\'Active Directory et les
synchronisant en créant un fichier de connexion yaml

``` /yaml
kind: LDAPSyncConfig
apiVersion: v1
url: ldap://ldap-win.abes.fr
bindDN: CN=acces_ldap_okd,OU=applicatif,OU=Utilisateurs,DC=levant,DC=abes,DC=fr
bindPassword: 
insecure: false
augmentedActiveDirectory:
    groupsQuery:
        baseDN: "OU=DSIN,OU=Groupes de securite,DC=levant,DC=abes,DC=fr"
        scope: sub
        derefAliases: never
    groupUIDAttribute: dn
    groupNameAttributes: [ cn ]
    usersQuery:
        baseDN: "OU=personnels,OU=Utilisateurs,DC=levant,DC=abes,DC=fr"
        scope: sub
        derefAliases: never
        filter: (objectclass=inetOrgPerson)
        pageSize: 0
    userNameAttributes: [ sAMAccountName ]
    groupMembershipAttributes: [ memberOf ]
```

Il existe deux options pour cela:

1.  activeDirectory:
    1.  tous les groupes de sécurité d\'Active Directory par défaut
    2.  le nom des groupes importés sera le DN AD.
2.  augmentedActiveDirectory:
    1.  On peut personnaliser les noms des Groupes dans OKD
    2.  importer les groupes d\'une branche, pour notre usage ce sera
        `DSIN`

Nous choisirons `augmentedActiveDirectory` parce qu\'il permet d\'être
au plus juste des utilisateurs qui vont être amenés à se servir d\'OKD.

Il reste à synchroniser les groupes sur la base de ce fichier:

    oc adm groups sync --sync-config=active_directory_config.yaml --confirm

Si les groupes sont modifiés ou effacés dans AD, alors on peut lancer
une synchronisation de façon à répercuter l\'effacement des groupes
disparus dans OKD:

    oc adm prune groups --sync-config=/path/to/ldap-sync-config.yaml --confirm

## Ajout de droits RBAC par groupe

Ajout des droits `cluster-admin` au groupe SIRE

    oc adm policy add-cluster-role-to-group cluster-admin SIRE --rolebinding-name=cluster-admin

Retrait des droits `cluster-admin` au groupe SIRE

    oc adm policy remove-cluster-role-from-group cluster-admin SIRE  --rolebinding-name=cluster-admin

Énumération des utilisateurs ayant pour rôle RBAC `cluster-admin`

    oc describe clusterrolebinding.rbac cluster-admin
