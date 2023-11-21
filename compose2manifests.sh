#!/bin/bash
# 23/10/28 NBT
# Script de conversion d'un fichier docker-compose.yaml en manifests k8s
# Génère 3 types de manifest: deploy, services, configMap
# Nécessite les paquets jq, yq, moreutils, docker-compose, kompose
# Usage:
# ./compose2manifests.sh [ prod || test || dev || local ] [ appli_name ] [default || '' || secret || env_file | help] [kompose] [helm]\n"

help () {
	echo -e "usage: ./compose2manifests.sh [ prod || test || dev || local ] [ appli_name ] [default || '' || secret || env_file | help] [kompose] [helm]\n"
	echo -e "dev|test|prod: \tenvironnement sur lequel récupérer le .env. Local: fournir manuellement les '.env' et 'docker-compose.yml'"
	echo -e "appli_name: \t\tnom de l'application à convertir"
	echo -e "default or '' : \tGenerates cleaned appli.yml compose file to plain k8s manifests "
	echo -e "env_file: \t\tGenerates cleaned advanced appli.yml with migrating plain 'environment' \n\t\t\tto 'env_file' statement, will be converted into k8s configmaps"
	echo -e "secret: \t\tThe same as env_file, in addition generates advanced appli.yml with \n\t\t\tmigrating all vars containing 'PASSWORD' or 'KEY' as keyword to secret,\n\t\t\twill be converted into k8s secrets"
	echo -e "kompose: \t\tConverts appli.yml into plain k8s manifests ready to be deployed with \n\t\t\t'kubectl apply -f *.yaml"
	echo -e "helm: \t\t\tKompose option that generates k8s manifest into helm skeleton for appli.yml\n"
	echo -e "example: ./compose2manifests.sh local item secret kompose\n"
	echo -e "example: ./compose2manifests.sh prod qualimarc secret kompose helm\n"
	exit 1
}

case $2 in
	'' | help | --help)
		help;;
	*)
		;;
esac

case $3 in
	default | '' | secret | env_file)
        ;;
	*)
		help;;
esac

echo "###########################################"
echo "ETAPE 1: Initialisation du projet..."
echo "1> Nettoyage..."
if [ -f ./okd ];then rm -rf okd; fi
shopt -s extglob
rm -rf !(.env|docker-compose.yml|*.sh|.git|.|..)
echo -e "\n"

if [ "$3" = "clean" ]; then
	echo "Cleaned Wordir";
	exit;
fi

echo -e "\n"

echo "ETAPE 2: Installation des pré-requis"
install_bin () {
  if ! [ -f /usr/local/bin/$1 ] && ! [ -f /usr/bin/$1 ];then
        case $1 in
                jq)
                        BIN="jqlang/jq/releases/latest/download/jq-linux-amd64";;
                yq)
                        BIN="mikefarah/yq/releases/latest/download/yq_linux_amd64";;
                docker-compose)
                        BIN="docker/compose/releases/latest/download/docker-compose-linux-x86_64";;
                kompose)
                        BIN="kubernetes/kompose/releases/latest/download/kompose-linux-amd64";;
                *)
                ;;
        esac
        echo "Installing $1..."
        sudo wget -q https://github.com/${BIN} -O /usr/local/bin/$1 &&  sudo  chmod +x /usr/local/bin/$1
  fi
  if ! [ -f /usr/bin/sponge ];then
                echo "Installing sponge..."
                case $(cat /etc/os-release | grep ID_LIKE) in \
        *debian*) \
                apt install moreutils -y;; \
        *rhel*) \
                if [[ "$(cat /etc/os-release | grep VERSION_ID)" =~ .*8.* ]];then
                dnf config-manager --set-enabled powertools powertools
                else
                dnf config-manager --set-enabled powertools crb
                fi
                dnf -q install moreutils -y;; \
        *) \
                echo "Not supported plateform!" \
                exit 1;; \
                esac
  fi
  case $1 in
          jq|yq) $1 --version;;
          kompose) echo "kompose $($1 version)";;
          *) $1 version;;
  esac
}

for i in jq yq docker-compose kompose; do install_bin $i; done

echo -e "\"

echo "ETAPE 3: Téléchargement du docker-compose"

if [[ "$1" == "prod" ]] || [[ "$1" == "test" ]] || [[ "$1" == "dev" ]]; then
		echo "##### Avertissement! #######################"
		echo "Il faut que clé ssh valide sur tous les diplotaxis{} pour continuer...."
		echo "Continuer? (yes/no)"
		read continue
		if [[ "$continue" != "yes" ]]; then 
			echo "Please re-execute the script after having installed your ssh pub keys on diplotaxis{}-${1}"
			exit 1;
		fi
		echo "Ok, let's go on!"
		diplo=$(for i in {1..6}; \
		do ssh root@diplotaxis$i-${1} docker ps --format json | jq --arg toto "diplotaxis${i}-${1}" '{diplotaxis: ($toto), nom: .Names}'; \
		done \
		| jq -rs --arg var "$2" '.[] | select(.nom | test("\($var)-watchtower"))| .diplotaxis'); \
		mkdir $2-docker-${1} && cd $2-docker-${1}; \
		echo "Getting docker-compose.file from GitHub";  \
		wget -N https://raw.githubusercontent.com/abes-esr/$2-docker/develop/docker-compose.yml 2> /dev/null; \
		echo $PWD; \
		rsync -av root@$diplo:/opt/pod/$2-docker/.env .; \
elif [[ "$1" == local ]];then
		if ! [[ -f ./docker-compose.yml ]]; then
			echo "If $2 is hosted on gitlab.abes.fr, you can download your docker-compose.yml (yes/no)?"
			read rep
			if [[ "$rep" == "yes" ]];then
				echo "Please provide your gitlab private token (leave empty if public repo)"
				read token
				ID=$(curl -s --header "PRIVATE-TOKEN: $token" https://git.abes.fr/api/v4/projects | \
				jq -r --arg toto "$2" '.[] | select(.name==$toto)| .id')
				curl -s --header "PRIVATE-TOKEN: $token" https://git.abes.fr/api/v4/projects/${ID}/repository/files/docker-compose.yml/raw?ref=main > docker-compose.yml
				vi docker-compose.yml
				if ! [[ -f ./.env ]];then
					echo "Please manually rovide a valid \".env\" file"
					exit 1
				fi
			else
				echo "You may manually copy your \"docker-compose.yml\" and \".env\" file into $pwd"
				exit 1
			fi
		fi
		if ! [[ -f .env ]];then
			echo "Please provide a valid \".env\" file to continue"
			exit 1;
		fi
elif [[ "$1" != "local" ]]; then
		echo "Valid verbs are 'github' or 'local'"
		exit 1;
elif ! test -f .env || ! test -f docker-compose.yml; then
		echo -e "No valid files have been found\nCopy your '.env' and your 'docker-compose.yml in $PWD'";
		exit 1;
fi 

echo "2> Définition du nom du projet"
# NAME=$(cat docker-compose.yml | yq eval -o json | jq -r '[.services[]]| .[0].container_name' | cut -d'-' -f1)
NAME=$2
echo -e "projet: $NAME\n"

echo "############################################"


echo "ETAPE 2: Conversion du  en manifests Kubernetes"

message () {
	if [ $(echo $?) = "0" ]; 
		then 
			echo "...OK"; 
		else echo "echec!!!"; 
		exit 1;
	fi 
}

# 1> Résolution du .env
echo -e "1> #################### Résolution du .env ####################\n"
docker-compose config > $NAME.yml
message
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

message
echo -e "\n"

#### NBT 231108
#### insertion de la clé "secrets" dans chacun des services de docker-compose.yml
#### prend en paramètre le nom du fichier docker-compose.yml

CLEANED="$NAME.yml"

if [ -n "$3" ]; then
		echo "on continue"
	if [ "$3" == 'secret' ] || [ "$3" == 'env_file' ]; then

		if [ "$3" = "secret" ]; then

			######  transformation du docker-compose.yml en liste réduite ######
			# SMALL_LIST=$(cat $CLEANED | yq eval - -o json | jq '[.services[]|  {(.container_name): .environment}]') 
			SMALL_LIST=$(cat $CLEANED | yq eval - -o json | jq '.services|to_entries[] | {(.key): .value.environment}'| jq -s)
			#echo $SMALL_LIST| yq eval -P
			message

			###### select variable name filtering by KEY or PASSWORD ####
			FILTER_LIST=$(echo $SMALL_LIST | yq eval - -o json \
							| jq '.[]|to_entries[]|try {key:.key,value:.value|to_entries[]} | select(.value.key | test("KEY|PASSWORD"))' \
							| jq -s )
			message

			###### obtention d une paire KEY:services #######
			PAIR_LIST=$(for i in $(echo $FILTER_LIST | jq -r '.[].value.key' ); \
					do tata=$(echo $FILTER_LIST | jq -r --arg toto "$i" '.[] |select(.value.key==$toto)|.key'); \
						for j in $tata; do echo "$i:$j"; \
								done; \
					done | sort -u )
			message

			###### Injection dans le json #####
			for i in $(echo $PAIR_LIST); \
				do export KEY=$(echo $i| cut -d':' -f1); \
				export service=$(echo $i| cut -d':' -f2-); \
				cat $CLEANED | yq eval - -o json| jq --arg toto "$service" --arg tata "$KEY|tr [:upper:] [:lower:]" '.services[$toto].secrets |= . + [$tata]' \
					| yq eval - -P | sponge $CLEANED; \
				done
			message
		
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
			message
		fi

		########### Conversion du environment en env_file ############

		# 3> Génération des {service}.env à partir du docker-compose.yml
		echo -e "3> #################### Génération des {service}.env ####################\n"
		for i in $(cat $CLEANED|yq eval -ojson|jq -r --arg var "$i" '.services|to_entries|map(select(.value.environment != null)|.key)|flatten[]'); \
			do 	cat $CLEANED | \
				yq eval - -o json |\
				jq -r --arg var "$i" '.services[$var].environment' | \
				egrep -v 'KEY|PASSWORD' | \
				yq eval - -P| \
				sed "s/:\ /=/g" > $i.env; 
			done
		message

		# 4> Déclaration des {services.env} dans docker-compose.yml
		echo -e "4> #################### Déclaration des {services.env} ####################\n"
		for i in $(cat $CLEANED|yq eval -ojson|jq -r --arg var "$i" '.services|to_entries|map(select(.value.environment != null)|.key)|flatten[]'); \
			do echo $i; cat $CLEANED | \
						yq eval - -o json | \
						jq -r  --arg var "$i" '.services[$var]."env_file" = $var +".env"' | \
						sponge $CLEANED ; \
			done
		message
		echo -e "\n"



	# 5> Suppression des environnements et nettoyage final
	echo -e "5> #################### Suppression des environnements et nettoyage final ####################\n"
	cat $CLEANED \
	| jq 'del (.services[].environment)' \
	| jq 'del(.networks)' \
	| jq 'del(.services[].networks)' \
	| jq 'del(.services[].labels."com.centurylinklabs.watchtower.scope")' \
	| yq eval - -P | sponge $CLEANED

message
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
message
fi

cat $CLEANED 
echo -e "\n"

# Patch *.txt file to remove '\n' character based in 64
patch_secret () {
	for i in $(ls *secret*); \
		do  \
			echo "Patching $i..."; 
			cat $i | yq eval -ojson \
				   | jq -r '.data|=with_entries(.value |=(@base64d|sub("\n";"")|@base64))' \
				   | sponge $i; \
		done
}

if [ -n "$4" ] && [ "$4" = "kompose" ]; then
	# 6> génération des manifests
	echo -e "6> #################### génération des manifests ####################\n"
	if [ -n "$5" ] && [ "$5" = "helm" ]; then  
		kompose -f $CLEANED convert -c
		cd $NAME/templates
		patch_secret
	else
		kompose -f $CLEANED convert
		patch_secret
	fi
fi

echo -e "\nYou are ready to deploy $NAME application into OKD\n"
case $1 in
	local) echo "Chose your OKD environment and run \'oc apply -f \"*.yaml\"\'\n";;
	*) echo "Connect to your $1 OKD environment and run \'oc apply -f \"*.yaml\"\'\n";;
esac

# cat qualimarc.yml | yq eval -ojson| jq -r '.services|to_entries[]|select(.key=="qualimarc-db-dumper")|.value.volumes|map(.source)|flatten[]'
# cat qualimarc.yml | yq eval -ojson| jq -r '.services|to_entries[]|select(.key=="qualimarc-db-dumper")|.value.volumes|map(.target)|flatten[]'


