# CI/CD #

## Objectifs

L\'intégration continue `CI` concerne l\'intégration du code et de la
construction (build) de l\'image tandis que le déploiement continu `CD`
traite de la façon de déployer la nouvelle image dans l\'infrastructure
adjacente.

Notre infrastructure actuelle s\'appuit sur le **CI/CD** GitHbub
actions/Watchtower

## Cas d\'usage

Dans le cadre de la migration des applications Docker vers Kubernetes,
nous allons voir quelles sont les façons d\'intégrer le CI/CD dans
Kubernetes/Openshift.

Pour ce faire, nous allons nous appuyer sur le cas de figure où un
fichier docker-compose.yml définit un service avec la directive `build`.
On retrouve par exemple cette directive dans le service **abesstp-web**
et **abesstp-web-cron** dans
<https://github.com/abes-esr/abesstp-docker/blob/develop/docker-compose.yml>

``` /yaml
services:
  abesstp-web:
    build: ./images/abesstp-web
    image: abesstp-web:php-5.6.40-apache
...
```

## CI/CD sur Openshift

[Déploiement avec les APIs natives Openshift](buildConfig.md)

## Build initial et CD sur Kubernetes

[Déploiement sur Kubernetes](deployment.md)