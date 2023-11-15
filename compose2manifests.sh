#!/bin/bash
# 23/10/28 NBT
# Script de conversion d'un fichier docker-compose.yaml en manifests k8s
# Génère 3 types de manifest: deploy, services, configMap
# Nécessite les paquets jq, yq, moreutils, docker-compose, kompose
# Usage:
# ./compose2manifests.sh [ prod || test || dev || local ] [ appli_name ] [default || '' || secret || env_file | help] [kompose] [helm]\n"

case $2 in
	'' | help | --help)
	 	echo -e "usage: ./compose2manifests.sh [ prod || test || dev || local ] [ appli_name ] [default || '' || secret || env_file | help] [kompose] [helm]\n"
		echo -e "diplotaxis{n}: nom du diplotaxis sur lequel récupérer le .env. Local: fournir manuellement les '.env' et 'docker-compose.yml'"
		echo -e "appli_name: nom de l'application à convertir"
		echo -e "default or '' : \tGenerates cleaned appli.yml compose file to plain k8s manifests "
		echo -e "env_file: \t\tGenerates cleaned advanced appli.yml with migrating plain 'environment' \n\t\t\tto 'env_file' statement, will be converted into k8s configmaps"
		echo -e "secret: \t\tThe same as env_file, in addition generates advanced appli.yml with \n\t\t\tmigrating all vars containing 'PASSWORD' or 'KEY' as keyword to secret,\n\t\t\twill be converted into k8s secrets"
		echo -e "kompose: \t\tConverts appli.yml into plain k8s manifests ready to be deployed with \n\t\t\t'kubectl apply -f *.yaml"
		echo -e "helm: \t\t\tKompose option that generates k8s manifest into helm skeleton for appli.yml\n"
		echo -e "example: ./compose2manifests.sh secret kompose helm"
		echo -e "example: ./compose2manifests.sh diplotaxis1 qualimarc secret kompose helm\n ./compose2manifests.sh local qualimarc secret kompose helm"
		exit 1
		;;
	*)
		;;
esac

case $3 in
	default | '' | secret | env_file)
        ;;
	*)
	 	echo -e "usage: ./compose2manifests.sh [ prod || test || dev || local ] [ appli_name ] [default || '' || secret || env_file | help] [kompose] [helm]\n"
		echo -e "diplotaxis{n}: nom du diplotaxis sur lequel récupérer le .env. Local: fournir manuellement les '.env' et 'docker-compose.yml'"
		echo -e "appli_name: nom de l'application à convertir"
		echo -e "default or '' : \tGenerates cleaned appli.yml compose file to plain k8s manifests "
		echo -e "env_file: \t\tGenerates cleaned advanced appli.yml with migrating plain 'environment' \n\t\t\tto 'env_file' statement, will be converted into k8s configmaps"
		echo -e "secret: \t\tThe same as env_file, in addition generates advanced appli.yml with \n\t\t\tmigrating all vars containing 'PASSWORD' or 'KEY' as keyword to secret,\n\t\t\twill be converted into k8s secrets"
		echo -e "kompose: \t\tConverts appli.yml into plain k8s manifests ready to be deployed with \n\t\t\t'kubectl apply -f *.yaml"
		echo -e "helm: \t\t\tKompose option that generates k8s manifest into helm skeleton for appli.yml\n"
		echo -e "example: ./compose2manifests.sh diplotaxis1 qualimarc secret kompose helm\n ./compose2manifests.sh local qualimarc secret kompose helm"
		exit 1
		;;
esac

echo "###########################################"
echo "ETAPE 1: Initialisation du projet..."
echo "1> Nettoyage..."
shopt -s extglob
rm -rf !(.env|docker-compose.yml|*.sh)
echo -e "\n"

if [ "$3" = "clean" ]; then
	echo "Cleaned Wordir";
	exit;
fi

echo "ETAPE 2: Téléchargement du docker-compose"

if [[ "$1" == "prod" ]] || [[ "$1" == "test" ]] || [[ "$1" == "dev" ]]; then
		diplo=$(for i in {1..6}; \
		do ssh root@diplotaxis$i-${1} docker ps --format json | jq --arg toto "diplotaxis${i}-${1}" '{diplotaxis: ($toto), nom: .Names}'; \
		done \
		| jq -rs --arg var "$2" '.[] | select(.nom | test("\($var)-watchtower"))| .diplotaxis'); \
		mkdir $2-docker-${1} && cd $2-docker-${1}; \
		echo "Getting docker-compose.file from GitHub";  \
		wget -N https://raw.githubusercontent.com/abes-esr/$2-docker/develop/docker-compose.yml 2> /dev/null; \
		echo $PWD; \
		rsync -av root@$diplo:/opt/pod/$2-docker/.env .; \
elif [ "$1" != "local" ]; then
		echo "Valid verbs are 'github' or 'local'"
		exit 1;
elif ! test -f .env || ! test -f docker-compose.yml; then
		echo -e "No valid files have been found\nCopy your '.env' and your 'docker-compose.yml in $PWD'";
		exit 1;
fi 

echo "2> Définition du nom du projet"
# NAME="${NAME_tmp=$(cat docker-compose.yml | yq eval -o json | jq -r '[.services[]]| .[0].container_name' | cut -d'-' -f1)}.yml"
NAME=$(cat docker-compose.yml | yq eval -o json | jq -r '[.services[]]| .[0].container_name' | cut -d'-' -f1)
echo -e "projet: $NAME\n"

echo "############################################"


echo "ETAPE 2: Conversion du  en manifests Kubernetes"

# 1> Résolution du .env
echo -e "1> #################### Résolution du .env ####################\n"
docker-compose config > $NAME.yml
if [ $(echo $?) = "0" ] ; then echo "...OK"; else echo "echec!!!"; exit 1;fi 
# 2> Conversion initiale du docker-compose.yml
echo -e "2> #################### Conversion initiale du $NAME.yml ####################\n"
docker-compose -f $NAME.yml convert --format json \
| jq 'del (.services[].command)' \
| jq 'del (.services[].entrypoint)' \
| jq --arg toto "$NAME" 'del (.services."\($toto)-watchtower")' \
| jq 'del (.services[]."depends_on")' \
| jq 'del (.services."theses-elasticsearch-setupcerts")' \
| jq 'del (.services."theses-elasticsearch-setupusers")' \
| jq 'del (.services."theses-api-diffusion-poc")' \
| jq 'del (.services[].mem_limit)'\
| docker-compose -f - convert | sponge $NAME.yml

if [ $(echo $?) = "0" ] ; then echo "...OK"; else echo "echec!!!"; exit 1;fi 

#### NBT 231108
#### insertion de la clé "secrets" dans chacun des services de docker-compose-resolved-cleaned.yaml
#### prend en paramètre le nom du fichier docker-compose-resolved-cleaned.yaml

CLEANED="$NAME.yml"

if [ -n "$3" ]; then
		echo "on continue"
	if [ "$3" == 'secret' ] || [ "$3" == 'env_file' ]; then

		if [ "$3" = "secret" ]; then

			######  transformation du docker-compose-resolved-cleaned.yaml en liste réduite ######
			# SMALL_LIST=$(cat $CLEANED | yq eval - -o json | jq '[.services[]|  {(.container_name): .environment}]') 
			SMALL_LIST=$(cat $CLEANED | yq eval - -o json | jq '.services|to_entries[] | {(.key): .value.environment}'| jq -s)
			#echo $SMALL_LIST| yq eval -P
			if [ $(echo $?) = "0" ] ; then echo "...OK"; else echo "echec!!!"; exit 1;fi 

			###### select variable name filtering by KEY or PASSWORD ####
			FILTER_LIST=$(echo $SMALL_LIST | yq eval - -o json \
							| jq '.[]|to_entries[]|try {key:.key,value:.value|to_entries[]} | select(.value.key | test("KEY|PASSWORD"))' \
							| jq -s )
			if [ $(echo $?) = "0" ] ; then echo "...OK"; else echo "echec!!!"; exit 1;fi 

			###### obtention d une paire KEY:services #######
			PAIR_LIST=$(for i in $(echo $FILTER_LIST | jq -r '.[].value.key' ); \
					do tata=$(echo $FILTER_LIST | jq -r --arg toto "$i" '.[] |select(.value.key==$toto)|.key'); \
						for j in $tata; do echo "$i:$j"; \
								done; \
					done | sort -u )
			if [ $(echo $?) = "0" ] ; then echo "...OK"; else echo "echec!!!"; exit 1;fi 

			###### Injection dans le json #####
			for i in $(echo $PAIR_LIST); \
				do export KEY=$(echo $i| cut -d':' -f1); \
				export service=$(echo $i| cut -d':' -f2-); \
				cat $CLEANED | yq eval - -o json| jq --arg toto "$service" --arg tata "$KEY" '.services[$toto].secrets |= . + [$tata]' \
					| yq eval - -P | sponge $CLEANED; \
				done
			if [ $(echo $?) = "0" ] ; then echo "...OK"; else echo "echec!!!"; exit 1;fi 
		
			###### Generating secret files from .env file  #####
			export var=$(echo $FILTER_LIST | jq  -r '.[].value.key') \
			# export data=$(echo $FILTER_LIST | jq  -r '.[].value.value') \
			for i in $(echo $var); \
			do export data=$(echo $FILTER_LIST | jq --arg tata "$i" -r '[.[].value | select(.key==$tata).value]|first')
				echo $data > $i.txt; \
				cat $CLEANED \
				| yq eval - -o json \
				| jq --arg toto $i '.secrets[$toto].file = $toto + ".txt"' \
				| yq eval - -P \
				| sponge $CLEANED; \
			done
			if [ $(echo $?) = "0" ] ; then echo "...OK"; else echo "echec!!!"; exit 1;fi 
		fi

		########### Conversion du environment en env_file ############

		# 3> Génération des {service}.env à partir du docker-compose-resolved-cleaned.yml
		echo -e "3> #################### Génération des {service}.env ####################\n"
		for i in $(cat $CLEANED | yq eval - -o json | jq -r '.services|keys|flatten[]'); \
			do echo $i; 
				# if [ "$3" = "secret" ]; 
				# 	then 
						cat $CLEANED | \
						yq eval - -o json |\
						jq -r --arg var "$i" '.services[$var].environment' | \
						egrep -v 'KEY|PASSWORD' | \
						yq eval - -P| \
						sed "s/:\ /=/g" > $i.env; \
			# 	else cat $CLEANED | \
			#             yq eval - -o json |\
			#             jq -r --arg var "$i" '.services[$var].environment' | \
			#             yq eval - -P| \
			#             sed "s/:\ /=/g" > $i.env; \
			# 	fi 
			done
		if [ $(echo $?) = "0" ] ; then echo "...OK"; else echo "echec!!!"; exit 1;fi 

		# 4> Déclaration des {services.env} dans docker-compose-resolved-cleaned.yml
		echo -e "4> #################### Déclaration des {services.env} ####################\n"
		for i in $(cat $CLEANED | yq eval - -o json | jq -r '.services|keys|flatten[]'); \
			do echo $i; cat $CLEANED | \
						yq eval - -o json | \
						jq -r  --arg var "$i" '.services[$var]."env_file" = $var +".env"' | \
						sponge $CLEANED ; \
			done
		if [ $(echo $?) = "0" ] ; then echo "...OK"; else echo "echec!!!"; exit 1;fi 
		echo -e "\n"



	# 5> Suppression des environnements et nettoyage final
	echo -e "5> #################### Suppression des environnements et nettoyage final ####################\n"
	cat $CLEANED \
	| jq 'del (.services[].environment)' \
	| jq 'del(.networks)' \
	| jq 'del(.services[].networks)' \
	| jq 'del(.services[].labels."com.centurylinklabs.watchtower.scope")' \
	| yq eval - -P | sponge $CLEANED

if [ $(echo $?) = "0" ] ; then echo "...OK"; else echo "echec!!!"; exit 1;fi 
	fi

else

# 5> Suppression des environnements et nettoyage final
echo -e "5> #################### Suppression des environnements et nettoyage final ####################\n"
cat $CLEANED \
| yq eval -o json \
| jq 'del(.networks)' \
| jq 'del(.services[].networks)' \
| jq 'del(.services[].labels."com.centurylinklabs.watchtower.scope")' \
| yq eval - -P | sponge $CLEANED

echo -e "\n"
if [ $(echo $?) = "0" ] ; then echo "...OK"; else echo "echec!!!"; exit 1;fi 
fi

cat $CLEANED 

if [ -n "$4" ] && [ "$4" = "kompose" ]; then
	# 6> génération des manifests
	echo -e "6> #################### génération des manifests ####################\n"
	if [ -n "$5" ] && [ "$5" = "helm" ]; then  
		kompose -f $CLEANED convert -c
	else
		kompose -f $CLEANED convert
	fi
fi


