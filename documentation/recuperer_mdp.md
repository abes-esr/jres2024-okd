# Récupérer un mot de passe

Les fichiers sont cryptés en base 64 dans OKD. On peut facilement les
récupérer dans l\'interface d\'OKD:

    Administrator => Workloads => Secrets

On choisit le namespace dans lequel se trouve le `secret` à décrypter,
le secret en question et on appuie `reveal value`

On peut faire la même chose avec `oc` (exemple qui suit avec un
bindPassword)

``` bash
oc get secret ldap-bind-password-676wf -o yaml -n openshift-config -ojsonpath={.data.bindPassword} |base64 -d
```

On peut adapter le jsonpath en fonction de la nature du password contenu
dans le `oc get secret`.
