#!/bin/bash
# 24/10/21 blanchet<at>abes.fr
# Script de conversion d'un fichier docker-compose.yaml en manifests k8s
# Génère pour chacun des services ces manifest: deploy, services, configMap, secret, persistentVolumeClaim
# Nécessite les paquets jq, yq, jc, moreutils, docker-compose, kompose
# Usage:
# ./compose2manifests.sh [ prod || test || dev || local ] [ appli_name ] [default || '' || secret || env_file | help] [kompose] [helm]\n"

help () {
	echo -e "usage: ./compose2manifests.sh [ prod || test || dev || local ] [ appli_name ] [default || '' || secret || env_file | help] [kompose] [helm]\n"
	echo -e "dev|test|prod: \tenvironnement sur lequel récupérer le .env. Local: fournir manuellement les '.env' et 'docker-compose.yml'"
	echo -e "appli_name: \t\tnom de l'application à convertir"
	echo -e "default or '' : \tGenerates cleaned appli.yml compose file to plain k8s manifests "
	echo -e "env_file: \t\tGenerates cleaned advanced appli.yml with migrating plain 'environment' \n\t\t\tto 'env_file' statement, will generate k8s \"configmaps\" for common vars and \"secrets\" for vars containing 'PASSWORD' or 'KEY' as keyword"
	echo -e "kompose: \t\tConverts appli.yml into plain k8s manifests ready to be deployed with \n\t\t\t'kubectl apply -f *.yaml"
	echo -e "helm: \t\t\tKompose option that generates k8s manifest into helm skeleton for appli.yml\n"
	echo -e "example: ./compose2manifests.sh local item env_file kompose\n"
	echo -e "example: ./compose2manifests.sh prod qualimarc default kompose helm\n"
	exit 1
}

ENV=$1
NAME=$2
VARS_TYPE=$3
KOMPOSE=$4
HELM=$5

# RED="31"
# GREEN="32"
MAGENTA="\e[35m"
GREEN="\e[92m"
YELLOW="\e[93m"
BLUE="\e[94m"
RED="\e[31m"
CYAN="\e[36m"
BOLDGREEN="\e[1;${GREEN}m"
ITALICRED="\e[3;${RED}m"
ENDCOLOR="\e[0m"
FAINT="\e[2m"
BOLD="\e[1m"
ITALICS="\e[3m"



case $NAME in
	'' | help | --help)
		help;;
	*)
		;;
esac

case $VARS_TYPE in
	default | '' | secret | env_file)
        ;;
	*)
		help;;
esac

blue () {
	echo -e "${BLUE}$1${ENDCOLOR}"
}

red () {
	echo -e "${RED}$1${ENDCOLOR}"
}

faint () {
	echo -e "${FAINT}$1${ENDCOLOR}"
}

italics () {
	echo -e "${ITALICS}$1${ENDCOLOR}"
}

bold () {
	echo -e "${BOLD}$1${ENDCOLOR}"
}

step () {
	echo -e "\n\n"${YELLOW}################################################################################################################################${ENDCOLOR}"
${YELLOW}STEP $1: $2${ENDCOLOR}"
}

title () {
	echo -e "\n${GREEN}$1> ##################################################${ENDCOLOR}
${GREEN}############ $2 ${ENDCOLOR}
${GREEN}#######################################################${ENDCOLOR}"
}

message () {
	if [ $(echo $?) = "0" ]; 
		then 
			echo -e "${BLUE}...OK${ENDCOLOR}"; 
		else echo -e "${RED}echec!!!${ENDCOLOR}"; 
		exit 1;
	fi 
}

step "1" "Project Initialization........"

title "1.1" "Cleaning working dir" 
if [ -f ./okd ]
	then rm -rf okd
fi

# Check potential previous existent sshfs mount 
sshfs=$( mount | grep sshfs )
if [ -n "$sshfs" ]
	then
		echo -e "There is one active sshfs mount, please unmount it before going on: \n"
		blue "$sshfs"
		exit 1
fi
shopt -s extglob
# rm -rf !(.env|docker-compose.yml|*.sh|.git|.|..)
rm -rf !(.env|docker-compose.yml|*.sh|.git|*.md|*.py|documentation|.|..)
message

if [ "$VARS_TYPE" = "clean" ]; then
	echo "Cleaned Wordir";
	exit;
fi

echo -e ""

# echo "1.2> #################### Installation des pré-requis ####################"
title "1.2" "Installation of pre-required features"

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
                        BIN="kubernetes/kompose/releases/download/v1.28.0/kompose-linux-amd64";;
				oc)
						wget -q okd-project/okd/releases/download/4.G1263.0-0.okd-2023-02-18-033438/openshift-client-linux-4.12.0-0.okd-2023-02-18-033438.tar.gz \
							 -O /usr/local/bin/ | \
						tar xzf -
						chmod +x {kubectl,oc};;
				jc)
						wget -q https://github.com/kellyjonbrazil/jc/releases/download/v1.25.3/jc-1.25.3-linux-x86_64.tar.gz \
							 -O /usr/local/bin/ | \
						tar xzf -
						chmod +x jc;;
                *)
                ;;
        esac
        echo "Installing $(blue $1)......................................."
        sudo wget -q https://github.com/${BIN} -O /usr/local/bin/$1 &&  sudo  chmod +x /usr/local/bin/$1
  fi
  if ! [ -f /usr/bin/sponge ];then
                echo "Installing sponge......................................."
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
		  jc) $1 -v |head -1;;
          *) $1 version;;
  esac
}

for i in jq yq docker-compose kompose oc jc; do install_bin $i; done

echo -ne "Application to deploy: " 
blue \"$NAME\"
namespace=$(oc config view --minify -o 'jsonpath={..namespace}')
api=$(oc config view --minify -o 'jsonpath={..server}')
echo -ne "Cluster k8s: "
blue $api
echo -ne "Namespace in use: "
blue "\"$namespace\"\n"
case $1 in
	test|dev|prod)
		echo -e "You will deploy appli $(blue \"$NAME\") from the Docker $(blue \"$1\") platform to\n$(blue \"$api\") k8s cluster in the $(blue \"$namespace\") namespace.\""
		;;
	local)
		echo -e "You will deploy appli $(blue \"$NAME\") from a docker-compose.yml file and a .env file (provided by yourself) to $(blue \"$api\") k8s cluster in the $(blue \"$namespace\") namespace."
		;;
		*)
		echo "Bad arguments"
		exit;;
esac

if [[ $(echo $namespace | grep $NAME > /dev/null && echo $?) != 0 ]];
	then
		echo -e "${YELLOW}!! Warning !! ${ENDCOLOR}: current OKD namespace $(blue \"$namespace\") may not correspond to the appli $(blue \"$NAME\") you are about to deploy.\n"
		read -p "$(italics "?? Enter the name of a new namespace relative to $(blue \"$NAME\")"): " namespace
		blue "$namespace"
fi
echo "################################################################################################################################"
echo -e ""

set_ssh_key() {

			if [[ $( ls ~/.ssh | grep "id" ) == '' ]]
				then
					read -p "$(italics "?? No pub keys have been found. Do you want to generate? $(faint "[y]")"): " yn3
					yn3=${yn3:-y}
					case $yn3 in
						[Yy]* )
							ssh-keygen;;
						[Nn]* )
							italics "You must first install some pub key before using this script"
							exit;;
					esac											
				else
					if [ -z "$key" ]; then 
						echo -e  "Here are the available public keys in your home directory:"
						for k in $(ls ~/.ssh/ |grep pub|cut -d"." -f1); do blue $k; done
						read -p "$(italics "?? Which one do you want to use to connect to your Docker hosts? $(faint "[id_rsa]")"): " key
						key=${key:-id_rsa}
						blue $key
					fi
			fi
}

testing_ssh() {

echo "Checking ssh connectivity to Docker hosts to bind ...."
for i in $docker_hosts
	do 
		SSH=$(ssh -q -o "BatchMode=yes" -o "ConnectTimeout=3" root@${i}.${domain} "echo 2>&1" && echo "OK" )
		if [[ $(echo $SSH) == "OK" ]]
			then 
				echo "Connexion to root@${i}.${domain} ........... $(blue OK)"
			else 
				echo "Connexion to root@${i}.${domain} ........... $(red NOK)"
				read -p "$(italics "?? Do you want to install $key to root@${i}.${domain}: $(faint "[y]")?") " yn
				yn=${yn:-y}
				while true; do
					case $yn in
						[Yy]* )
							set_ssh_key
							echo -e "Installing pub keys......."
							ssh-copy-id root@${i}.${domain} > /dev/null
							message
							break;;
						[Nn]* )
							italics "You must first install some pub key before using this script"
							exit
							break;;							
					esac; done
		fi
	done

}

# Check ssh key presence 
set_ssh_key

# Docker hosts domain identification
dom=$(hostname -d)
read -p "$(italics "?? Please enter the domain (default is the one of the bastion) $(faint [$dom]): ")" domain2
domain=${domain:-$dom}
blue $domain

echo ""


ask_testing_ssh() {
echo -e "${YELLOW}!!! Warning !!!${ENDCOLOR}"
read -p "$(italics "?? Do you want to check ssh connectivity? If a host is not reacheable, pub key will be installed.[no]: ")" yn
yn=${yn:-n}
while true; do
	case $yn in
		[Yy]* )
			testing_ssh
			break;;
		[Nn]* )
			echo "Assuming Docker hosts are available without any password..."
			break;;
	esac
done
}

fetch() {
	if [[ -f "$1" ]];
		then
			echo "$(blue \"$1\") ready to be used"
		else
			if [[ $1 == "docker-compose.yml" ]]
				then
					italics "\"$1\" has not been found. Please check https://raw.githubusercontent.com/abes-esr/$NAME-docker/develop/docker-compose.yml and retry"
			elif [[ $1 == ".env" ]]
				then
					echo "$(blue \"$1\") has not been found. Please check $(blue $docker_host:/opt/pod/$NAME-docker/.env) and retry"
			fi
			exit
	fi
}

get_running_docker() {
		echo ""
		read -p "$(italics "?? If you know the Docker host where \"$NAME\" is currently running on, please enter the hostname (not fqdn), else type \"enter\" to automatically find it: ")" hostname
		# hostname=${hostname:-diplotaxis2-test}
		if [ -z $hostname ]
			then
				docker_hosts=
				read -p "$(italics "?? Please enter the list of your Docker hosts hostnames: ")" docker_hosts
				docker_hosts=${docker_hosts:-"diplotaxis1 diplotaxis2 diplotaxis3 diplotaxis4 diplotaxis5 diplotaxis6 diplotaxis7"}
				set -- $(echo $docker_hosts)
				if [[ -n $ENV ]] && [[ "$ENV" != "local" ]]; 
					then
						set -- "${@/%/-$ENV}"
				fi
				docker_hosts=$(echo $@)
				blue "$docker_hosts"
				title "1.4" "SSH connexion validation"
				ask_testing_ssh
				echo "Searching which Docker host \"$NAME\" is currently running on ......"

				NAME_SHORT=$(echo $NAME | cut -d"-" -f1)

				diplo=$( \
						for i in $docker_hosts
							do 
								ssh root@${i}.${domain} docker ps --format json | jq --arg i "${i}" '{"docker_host": ($i), nom: .Names}'; \
							done \
							| jq -rs --arg docker_hosts "$i" --arg var "$NAME_SHORT" '[.[] | select(.nom | test("^\($var)-.*"))]|first|."docker_host"'
						); \
			else
				diplo="$hostname"
		fi

		blue "\"$NAME\" is running on $diplo\n"
		mkdir $NAME-docker-${ENV} && cd $NAME-docker-${ENV}

		docker_host="${diplo}.${domain}"
}

if [[ "$ENV" == "prod" ]] || [[ "$ENV" == "test" ]] || [[ "$ENV" == "dev" ]]; then
		echo -e ""

		echo "Ok, let's go on!"

		title "1.3" "Docker host search"
		get_running_docker

		read -p "$(italics "?? Choose docker-compose.yml method $(faint "[docker_host)|github]"): ")" method
		method=${method:-docker_host}
		blue "$method"
		case $method in 
			github )
				italics "Fetching \"docker-compose.yml\" from GitHub.......................................";  \
				read -p "$(italics "?? Enter DockerHub URL docker-compose.yml path"): " path
				path=${path:-https://raw.githubusercontent.com/abes-esr/$NAME-docker/develop/docker-compose.yml}
				wget -N $path 2> /dev/null; \
				fetch "docker-compose.yml"
				echo "";;
			docker_host )
				echo "Fetching \"docker-compose.yml\" from $docker_host .......................................";  \
				read -p "$(italics "?? Enter docker-compose.yml path on host \"$docker_host\" $(faint [/opt/pod/$NAME-docker]): ")" path
				path=${path:-/opt/pod/$NAME-docker}
				rsync -a root@$docker_host:$path/docker-compose.yml . ; \
				fetch "docker-compose.yml"
				echo "";;
		esac

		echo "Fetching \".env\" from $docker_host Docker host..........................................."
		rsync -a root@$docker_host:/opt/pod/$NAME-docker/.env .; \
		fetch ".env"
		echo ""

elif [[ "$ENV" == local ]];then
		get_running_docker
		if ! [[ -f ../docker-compose.yml ]]; then
				echo "There is no current docker-compose.yml file for \"$NAME\" in $(pwd)"
				read -p "$(italics "?? Choose docker-compose.yml method $(faint "[docker_host|gitlab|manual]"): ")" method
				method=${method:-docker_host}
				case $method in 
					gitlab )
						read -p "$(italics "?? If $NAME is hosted on gitlab.abes.fr, you can download your docker-compose.yml $(faint "(y/n)").......................................?")" rep
						if [[ "$rep" == "y" ]];then
							read -p "$(italics "?? Please provide your gitlab private token (leave empty if public repo):....................................... ")" token
							ID=$(curl -s --header "PRIVATE-TOKEN: $token" https://git.abes.fr/api/v4/projects | \
							jq -r --arg name "$NAME" '.[] | select(.name==$name)| .id')
							curl -s --header "PRIVATE-TOKEN: $token" https://git.abes.fr/api/v4/projects/${ID}/repository/files/docker-compose.yml/raw?ref=main > docker-compose.yml
							vi docker-compose.yml
						else
							echo "Can't continue... You may previously manually copy your \"docker-compose.yml\" and \".env\" file into $pwd"
							exit 1
						fi ;;
					docker_host ) 
						echo "Fetching \"docker-compose.yml\" from $docker_host .......................................";  \
						read -p "$(italics "?? Enter docker-compose.yml path on host \"$docker_host\" $(faint "[/opt/pod/$NAME-docker]"): ")" path
						path=${path:-/opt/pod/$NAME-docker}
						rsync -a root@$docker_host:$path/docker-compose.yml . ; \
						fetch "docker-compose.yml"
						echo "";;
					manual )
						echo "Please manually copy the docker-compose.yml to $PWD and re-execute this script"
						exit;;
				esac
			else
				cat ../docker-compose.yml |egrep -i "^$NAME$"
				if [ "$?" == 0 ];
					then
						echo "\"docker-compose.yml\" is already present and ready to be used for \"$NAME\".... "
					else
						echo "\"docker-compose.yml\" is already present but doesn't seem to belong to \"$NAME\".... "
						read -p "$(italics "?? Do you want to continue anyway? $(faint "[n]")")" yn
						if [ "$yn" == "n" ]; then echo -e "Please check \"$(cd .. && pwd)/docker-compose.yml\" content.\nExiting" ; exit; fi

				fi
		fi

		if ! [[ -f ../.env ]];then
			echo "Choose \".env\" method [docker_host|manual]: " method
			method=${method:-docker_host}
			case $method in 
				docker_host )
						echo "Fetching \".env\" from $docker_host .......................................";  \
						read -p "$(italics "?? Enter docker-compose.yml path on host \"$docker_host\" $(faint "[/opt/pod/$NAME-docker]]"): ")" path
						path=${path:-/opt/pod/$NAME-docker}
						rsync -a root@$docker_host:$path/.env . ; \
						fetch ".env"
						echo "";;
				manual )
						echo "Please manually provide a valid \".env\" file in the same directory as docker-compose.yml file ($PWD)"
						exit 1;;
			esac
			else
				cat ../.env |egrep -i "^$NAME$"
				if [ "$?" == 0 ];
					then
						echo "\".env\" is already present and ready to be used for \"$NAME\".... "
					else
						echo "\".env\" is already present but doesn't seem to belong to \"$NAME\".... "
						read -p "$(italics "?? Do you want to continue anyway? $(faint "[n]")")" yn
						if [ "$yn" == "n" ]; then echo -e "Please check \"$(cd .. && pwd)/.env\" content. \nExiting..." ; exit; fi
				fi
		fi

elif [[ "$ENV" != "local" ]]; then
		echo "Valid verbs are 'github' or 'local'"
		exit 1;
elif ! test -f .env || ! test -f docker-compose.yml; then
		echo -e "No valid files have been found\nCopy your '.env' and your 'docker-compose.yml in $PWD'";
		exit 1;
fi 

echo  ""
# Customizing .env
if test -f .env; 
	then
		read -p "$(italics "?? Do you want to customize your variable environment before the conversion to manifests?: $(faint "[n]") ")" yn
		yn=${yn:-n}
		while true; do
			case $yn in
				[Yy]* )
					vi .env
					break;;
				[Nn]* )
					break;;
			esac
		done
fi

echo -e "\n"

step "2" "Conversion des variables en objet secrets et configMaps"

title "2.1" ".env resolution"
docker-compose config --format json | yq -o json \
									| jq 	'.services
											|=with_entries(
															.key=(
																if .value|has("container_name") 
																then .value."container_name" 
																else . 
																end)
															)' \
											| yq -P \
											| sed 's/\.svc//g'> $NAME.yml
message

title "2.2" "Cleaning of $NAME.yml"

cat $NAME.yml \
			| yq -ojson \
			| jq --arg name "$NAME"  'del (.services."\($name)-watchtower")
									| del(..|nulls)
									| del(.services[].volumes[]?|select(.source|test("sock")))
									| del(.services[]."depends_on")
									| del(.services."theses-elasticsearch-setupcerts")
									| del(.services."theses-elasticsearch-setupusers")
									| del(.services."theses-api-diffusion-poc")
									| (if has("volumes") then .volumes|=with_entries(.key|=gsub("\\.";"-")) else . end)
									| .services[].volumes[]?|=(if .type=="bind" then . else .source|=gsub("\\.";"-") end)
									| .services|=with_entries(.value|=(select(has("volumes")).volumes |= sort_by((.type)) ))' \
			| yq -P | sponge $NAME.yml

message

#### insertion de la clé "secrets" dans chacun des services de docker-compose.yml
#### prend en paramètre le nom du fichier docker-compose.yml

CLEANED="$NAME.yml"

if [ -n "$VARS_TYPE" ] && [ "$VARS_TYPE" == 'env_file' ]
	then
		echo -e "on continue......................................."
			SMALL_LIST=$(cat $CLEANED | yq eval - -o json | jq '.services|to_entries[] | {(.key): .value.environment}'| jq -s)
			message

			###### select variable name filtering by KEY or PASSWORD ####
			FILTER_LIST=$(echo $SMALL_LIST | yq eval - -o json \
							| jq '.[]|to_entries[]|try {key:.key,value:.value|to_entries[]} | select(.value.key | test("KEY|PASS|SECRET"))' \
							| jq -s )
			message
		
			###### Generating secret files from .env file  #####
			export var=$(echo $FILTER_LIST | jq  -r '.[].value.key')
			for i in $(echo $var); \
				do 
					export data=$(echo $FILTER_LIST | jq --arg tata "$i" -r '[.[].value | select(.key==$tata).value]|first')
					echo $data > $(echo $i| sed 's/_/-/g' | tr '[:upper:]' '[:lower:]').txt; \
					cat $CLEANED \
					| yq eval - -o json \
					| jq --arg i $i '.secrets[$i|ascii_downcase|gsub("_";"-")].file = ($i|ascii_downcase|gsub("_";"-")) + ".txt"' \
					| yq eval - -P \
					| sponge $CLEANED; \
				done
			message

		########### Conversion du environment en env_file ############

		# Génération des {service}.env à partir du docker-compose.yml
		title "2.3" "Generation of \${services}.env"
		for i in $(cat $CLEANED|yq eval -ojson|jq -r --arg var "$i" '.services|to_entries|map(select(.value.environment != null)|.key)|flatten[]'); \
			do 	cat $CLEANED | \
				yq eval - -o json |\
				jq -r --arg var "$i" '.services[$var].environment' | \
				# egrep -v 'KEY|PASS|SECRET' | \
				yq eval - -P| \
				sed "s/:\ /=/g" > $i.env; 
			done
		message

		# Déclaration des variables contenant un secret dans le env_file
		for i in $(ls *.env); 
			do 
				for j in $(cat $i | egrep '(KEY|PASS|SECRET)'); 
					do 
						KEY=$(echo $j | cut -d"=" -f1);
						LINE=$(echo $KEY | cut -d"=" -f1 | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g');
						sed -i "s/.*$KEY.*/$KEY=\/run\/secrets\/$LINE/g" $i;
					done; 
			done 

		# Déclaration des {services.env} dans docker-compose.yml
		title "3.4" "Declaration of \${services}.env into deployments"
		for i in $(cat $CLEANED|yq eval -ojson|jq -r --arg var "$i" '.services|to_entries|map(select(.value.environment != null)|.key)|flatten[]'); \
			do echo $i; cat $CLEANED | \
						yq eval - -o json | \
						jq -r  --arg var "$i" '.services[$var]."env_file" = $var +".env"' | \
						sponge $CLEANED ; \
			done
		message

	# Suppression des environnements et nettoyage final
	title "3.5" "Cleaning"
	cat $CLEANED \
	| jq 'del (.services[].environment)' \
	| jq 'del(.networks)' \
	| jq 'del(.services[].networks)' \
	| jq 'del(.services[].labels."com.centurylinklabs.watchtower.scope")' \
	| yq eval - -P | sponge $CLEANED

message
	# fi

	else

# Suppression des environnements et nettoyage final
echo -e "5> #################### Suppression des environnements et nettoyage final ####################\n"
cat $CLEANED \
| yq eval -o json \
| jq 'del(.networks)' \
| jq 'del(.services[].networks)' \
| jq 'del(.services[].labels."com.centurylinklabs.watchtower.scope")' \
| yq eval - -P | sponge $CLEANED

message
fi
    
# Patch ReadOnlyMany pvc to ReadWriteOnly. The readOnly feature will be later executed with the "readOnly:"" true directive into deployment
patch_RWO () {
for i in $(grep ReadOnlyMany *persistent* |cut -d: -f1); 
	do 
		echo "Patching \n ReadOnlyMany modeAccess to ReadWriteOnce in $i......................................." 
		sed -i 's/ReadOnlyMany/ReadWriteOnce/g' $i; 
	done
}

patch_expose_auto () {
	for service in $services; 
		do 
			port=$(ssh root@$docker_host docker inspect $service | jq -cr '[.[].NetworkSettings.Ports|to_entries[]|.key|split("/")|.[0]'])
			port=${port:-[]}
			if [[ $port != '[]' ]]
				then
					blue "Patching ports $port for service $service ............"
					cat $CLEANED | yq -o json| jq | jq --arg service "$service" --argjson port "$port" '.services."\($service)".expose+=$port' \
					|sponge $CLEANED
			fi
		done
	cat $CLEANED | yq -P | sponge $CLEANED
}

patch_expose () {
	echo "You may define them one by one so as the conversion to be successfull"
	for service in $services; 
		do 
			read -p "$(italics "?? $service: Enter port number to expose the service $(faint "(press to leave empty)"): ")" port
			if [[ -n $service ]]
				then
					if [[ -n $port ]]
						then
							cat $CLEANED | yq -o json | jq --arg service "$service" --arg port "$port" '.services."\($service)".expose+=[ "\($port)" ]' \
							|sponge $CLEANED
					fi
			fi
		done
	cat $CLEANED | yq -P | sponge $CLEANED
}

# Patch *.txt file to remove '\n' character based in 64
patch_secret () {
	for i in $(ls *secret*yaml); \
		do  \
			echo "Patching \n character in $i......................................."; 
			cat $i | yq eval -ojson \
				   | jq -r '.data|=with_entries(.value |=(@base64d|sub("\n";"")|@base64))' \
				   | yq eval - -P \
				   | sponge $i; \
		done
}

# Patch secretKeys
patch_secretKeys () {
	for i in $(ls *deployment*); 
		do 
			echo "patching lowercase in $i......................................."
			cat $i| yq eval -ojson |
			jq '.spec.template.spec.containers
			|= map(
				(.env
				|= map(
					if (.name|test("SECRET|PASS|KEY"))
					then .valueFrom
						|= with_entries(.key="secretKeyRef"
							|.value.name=(.value.key|ascii_downcase|gsub("_";"-"))
							|.value.key|=(ascii_downcase|gsub("_";"-"))
							)
					else .
					end
					)
				)? // .
			)' |
			yq eval -P | sponge $i;
		done
}

# Patch networkpolicy to allow ingress
	patch_networkPolicy () {
	echo "patching ingress in $NAME-docker-$ENV-default-networkpolicy.yaml......................................."
	NETWORK=$(ls | grep networkpolicy)
	cat $NETWORK | 
		yq eval -ojson | 
		jq '.spec.ingress|=
				map(.from |= .+ [{"namespaceSelector":{"matchLabels":{ "policy-group.network.openshift.io/ingress": ""}}}])'|
		yq eval -P | sponge $NETWORK
}

create_pv2() {
nfs_mount_points=$(ssh root@$docker_host mount | \
					jc --mount | \
					jq -r '.[]|select(.type|test("nfs"))
					|{
					  path: .filesystem|split(":")|last, 
					  rep: .filesystem|split("/")|last|gsub("_";"-")|gsub("\\.";"-"),
					  mount_point: .mount_point, 
					  server: .filesystem|split(":")|first
					 }' \
				 )

for i in $(echo $nfs_mount_points|jq -r '."mount_point"|split("/")|last')
    do 
		nfs_service=$(cat $2.yml | \
					  yq -ojson | \
					  jq -r --arg i "$i" '.services|to_entries[]|select(.value|has("volumes"))|select(.value.volumes[]|select(.source|test("\($i)")))?' )
		if [[ -n $nfs_service ]]
			then 
				nfs_services=$nfs_service
		fi
    done

for i in $(echo $nfs_services|jq -r '.key'); do \
vol_nb=$(cat $NAME.yml|yq -ojson |jq --arg i "$i" --arg pwd "${PWD##*/}" -r '.services|to_entries[]
		|select(.key=="\($i)")
		|.value.volumes|length')

for ((index=0; index<$vol_nb; index++ )); do \
source=$(echo $nfs_services \
		|jq --arg i "$i" --arg pwd "${PWD##*/}" --arg index "$index" -r \
		'select(.key==$i)|(
							if (.value.volumes[$index|tonumber].source|split("\($pwd)/")|.[1] != null) 
							then .value.volumes[$index|tonumber].source|split("\($pwd)/")|.[1] 
							else .value.volumes[$index|tonumber].source|split("/")|.[1] 
							end
						  )' \
		)

NFS_PATH=$(echo $nfs_mount_points |jq -r --arg source "$source" 'select("\(.mount_point)"|test("\($source)$")).path')
NFS_SERVER=$(echo $nfs_mount_points |jq -r --arg source "$source" 'select("\(.mount_point)"|test("\($source)$")).server')

subpath=$(echo $nfs_services \
		|jq --arg i "$i" --arg pwd "${PWD##*/}" --arg source "$source" --arg index "$index" -r \
		'select(.key==$i)|(
							if (.value.volumes[$index|tonumber].source|split("\($pwd)/")|.[1] != null) 
							then .value.volumes[$index|tonumber].source|split("\($pwd)/")|.[1]|split("\($source)/")|last
							else .value.volumes[$index|tonumber].source|split("\($source)/")|last
							end
						  )' \
		)

if [ -n "$NFS_PATH" ];then
source_renamed=$(echo $source | sed 's/_/-/g' | sed 's/\./-/g' | sed 's/\//-/g' | tr '[:upper:]' '[:lower:]')
echo "Creating $i-pv$index-nfs-$source_renamed-persistentvolume.yaml ........................................."
cat <<EOF > $i-pv$index-nfs-$source_renamed-persistentvolume.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $i-pv${index}-nfs-$namespace-$ENV
spec:
  capacity:
    storage: 8Ti
  accessModes:
  - ReadWriteMany
  nfs:
    path: $NFS_PATH
    server: $NFS_SERVER
  persistentVolumeReclaimPolicy: Retain
EOF
create_pvc_nfs $ENV
patch_deploy_nfs $ENV
fi
done
done 

}

create_pvc_nfs() {

	echo "patching $source_renamed in $i-claim$index-nfs-persistentvolumeclaim.yaml ......................................."
	cat $i-claim$index-persistentvolumeclaim.yaml | 
		yq eval -ojson | 
			jq --arg project "$project" --arg name "$i" --arg env "$ENV" --arg namespace "$namespace" --arg index "$index" \
			'.metadata.name|="\($name)-claim\($index)-nfs-\($namespace)-\($env)"
			|.metadata.labels."io.kompose.service"|="\($name)-claim\($index)-nfs-\($namespace)-\($env)"
			|.spec.resources.requests.storage="8Ti"
			|.spec.volumeName="\($name)-pv\($index)-nfs-\($namespace)-\($env)"
			|.spec.storageClassName=""|.spec.accessModes=["ReadWriteMany"]' |
		yq eval -P | sponge $i-claim$index-nfs-persistentvolumeclaim.yaml
	echo "deleting $i-claim$index-persistentvolumeclaim.yaml"
	rm -f $i-claim$index-persistentvolumeclaim.yaml
}

patch_deploy_nfs() {

	oldname=$i-claim${index}
	newname="$i-claim${index}-nfs-${namespace}-$ENV"
	cat $i-deployment.yaml | yq -ojson | \
							jq --arg newname "$newname" --arg oldname "$oldname" --arg subpath "$subpath" \
							'(.spec.template.spec.containers[0].volumeMounts[]|select(.name=="\($oldname)"))+= ({subPath:"\($subpath)"}|.name|="\($newname)")|
							 (.spec.template.spec.volumes[]|select(.name=="\($oldname)"))|=(.name|="\($newname)"|.persistentVolumeClaim.claimName|="\($newname)")' | yq -P | sponge $i-deployment.yaml
}

patch_configmaps() {

	 for i in $(ls | grep "deployment")
	 	do 
			echo "patching configMaps in $i ......................................."
			claims=$(cat $i | yq -ojson| jq -r '.spec.template.spec.containers[].volumeMounts[]?|select((.mountPath|test("(\\.[^.]+)$")) and (.name|test("claim"))).name')

			for j in $claims
				do 
					echo "deleting ${j}-persistentvolumeclaim.yaml ......................................."
			        rm -f ${j}-persistentvolumeclaim.yaml
					cat $i | yq -ojson| \
					jq -r --arg j $j 'del(.spec.template.spec.volumes[]?|(select(.name=="\($j)")))'| \
					sponge $i
				done

			services=$(cat $i | yq -ojson| jq -r '.spec.template.spec.containers[].volumeMounts[]?|select((.mountPath|test("(\\.[^.]+)$")) and (.name|test("claim")))|(.name|split("-claim")|.[0]) + "-" + (.mountPath|split("/")|last|gsub("_";"-")|gsub("\\.";"-")|ascii_downcase)')

			for j in $services
				do cat $i | yq -ojson| \
					jq -r --arg j $j '((.spec.template.spec.containers[].volumeMounts[]?|select((.mountPath|test("(\\.[^.]+)$")) and (.name|test("claim")) )) |= {mountPath: .mountPath, name: ((.name|split("-claim")|.[0]) + "-" + (.mountPath|split("/")|last|gsub("_";"-")|gsub("\\.";"-")|ascii_downcase)), subPath: (.mountPath|split("/")|last)})|.spec.template.spec.volumes+=[{configMap: {defaultMode: 420, name: $j}, name: $j}]' | \
					sponge $i 
				done 
		done
}

create_configmaps() {
	CM=$(cat $NAME.yml | yq -o json | jq -r --arg pwd "$NAME-docker-$ENV" '.services[].volumes|select(.!=null)|.[]|select(.type == "bind")|select(.source|test("(\\.[^.]+)$"))|select(.source|test("sock")|not).source|split($pwd)|.[1]?')
	CM_RENAMED=$(cat $NAME.yml | yq -o json | jq -r --arg pwd "$NAME-docker-$ENV" '.services|to_entries[]|{name: .key, volumes: (.value|.volumes|select(.!=null)|.[]|select(.type == "bind")|select(.target|test("(\\.[^.]+)$"))|select(.target|test("sock")|not).target|split("/")|last)}|(.name + "-" + (.volumes|split("/")|last|gsub("\\/";"-")|gsub("\\.";"-")|gsub("\\_";"-")|ascii_downcase))')
	CM_RENAMED_short=$(cat $NAME.yml | yq -o json | jq -r --arg pwd "$NAME-docker-$ENV" '.services|to_entries[]|{name: .key, volumes: (.value|.volumes|select(.!=null)|.[]|select(.type == "bind")|select(.target|test("(\\.[^.]+)$"))|select(.target|test("sock")|not).target|split("/")|last)}|((.volumes|split("/")|last))')


	declare -a tab_CM
	declare -a tab_CM_RENAMED
	declare -a tab_CM_RENAMED_short

	index=-1
	for i in $CM 
		do 
			index=$(($index + 1))
			tab_CM[$index]=$i
		done 

	index=-1
	for i in $CM_RENAMED
		do 
			index=$(($index + 1))
			tab_CM_RENAMED[$index]=$i
		done 

	index=-1
	for i in $CM_RENAMED_short
		do 
			index=$(($index + 1))
			tab_CM_RENAMED_short[$index]=$i
		done 

	if [[ ! -d './volumes' ]]; 
		then
			mkdir volumes
	fi
	if [[ $index != -1 ]]
		then
			echo "Rep: $(pwd)"
			echo "Mounting root@$docker_host:/opt/pod/$NAME-docker/ ./volumes/"
			sshfs root@$docker_host:/opt/pod/$NAME-docker/ ./volumes/
			message

			for ((i=0; i<=$index; i++ ))
				do 
					echo "creating configMap file ${tab_CM_RENAMED[$i]}-configmap.yaml ......................................."
					oc create cm ${tab_CM_RENAMED[$i]} --from-file=./volumes/${tab_CM[$i]} --dry-run=client -o json  | jq -r --arg z  "${tab_CM_RENAMED_short[$i]}" '(if has("data") then .data|=with_entries(.key="\($z)") else .binaryData|=with_entries(.key="\($z)") end)' | yq -P > ${tab_CM_RENAMED[$i]}-configmap.yaml
				done
			fusermount -u $PWD/volumes
	fi
}

patch_labels() {
	for i in $(ls | egrep  "*env-configmap.yaml")
		do  
			echo "patching labels of $i .............. "
			cat $i |yq -ojson |jq -r '(.metadata|.labels."io.kompose.service")=.metadata.name' | yq -P | sponge $i 
		done
}


#Génération des manifests
step "3" "Docker-compose.yml conversion into Kubernetes manifests with the Kompose tool"


title "3.1" "Creating missing network manifests"
services=$(cat $CLEANED | yq -o json| jq -r '.services|to_entries[]|.value|select((has("ports") or has("expose"))|not)?|."container_name"')
if [[ -n $services ]]
	then
		echo -e "The following services don't have any explicit defined ports: \n$services"
		read -p "$(italics "?? Do you want to fetch ports from existing docker containers on $docker_host : $(faint "[y]")")" yn
		yn=${yn:-y}
		while true; do
			case $yn in
				[Yy]* )	
					patch_expose_auto
					break;;
				[Nn]* )
					patch_expose
					break;;
			esac
		done
fi

read -p "$(italics "?? Is this correct to be deployed? $(faint "[y]")............: ")" yn
yn=${yn:-y}
case $yn in
	[Yy]* )	blue "Converting \"docker-compose.yml\" into k8s manifests..."
			sleep 2;;
		* ) blue "Bye"
		    exit;;
esac

applis_svc=$(cat $NAME.yml | yq eval -ojson | \
	jq -r '.services|to_entries[]| [{services: .key, volumes: .value.volumes[]|select(.source|test("/appli"))}]?|.[].services'|uniq)
applis_source=$(cat $NAME.yml | yq eval -ojson | \
    jq -r '.services|to_entries[]| [{services: .key, volumes: .value.volumes[]|select(.source|test("/appli"))}]?|.[].volumes.source')
if [ -n "$KOMPOSE" ] && [ "$KOMPOSE" = "kompose" ]; then
	title "3.2" "Generation of manifests with Kompose"
	if [ -n "$HELM" ] && [ "$HELM" = "helm" ]; then  
		kompose -f $CLEANED convert -c
		cd $NAME/templates
	else
		kompose -f $CLEANED convert
	fi
	patch_RWO
	title "3.2.1" "Patching secret manifests"
	patch_secret
	patch_secretKeys
	title "3.2.2" "Patching network manifests"
	patch_networkPolicy $ENV
	title "3.2.3" "Patching storage manifests"
	create_pv2 $ENV $NAME
	title "3.2.4" "Patching file manifests"
	patch_configmaps $CLEANED
	patch_labels	
	# Création des object configMaps pour les volumes bind qui sont des fichiers et non des répertoires"
	create_configmaps $ENV
fi

title "3.3" "Patching multi-attached volumes"
# find targeted volumes 
export volumes=$(cat $CLEANED | yq eval -o json | jq -r '.services|to_entries[]|.value|select(has("volumes"))|.volumes[]|select((.type)=="volume").source'|uniq)

if [ -z "$volumes" ]; then  
	blue "No multi attached pvc found"; 
fi

# find if there is a nfs csi driver installed on the cluster
export nfs_csi=$(oc get csidrivers.storage.k8s.io -o json | jq -r '.items[].metadata|select(.name|test("nfs")).name')
export nfs_sc=$(oc get sc -o json | jq --arg nfs_csi $nfs_csi -r '.items[]|select(.provisioner|test("\($nfs_csi)")).metadata.name')

create_sc() {
    read -p "$(italics "?? Enter NFS server name $(faint "[methana.v102.abes.fr]")...........: ")" server_name
    server_name=${server_name:-methana.v102.abes.fr}
    read -p "$(italics "?? Enter NFS share $(faint "[/pool_SAS_2/OKD]")............: ")" nfs_share
    nfs_share=${nfs_share:-/pool_SAS_2/OKD}
    cat <<EOF | oc apply -f -
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs-csi
provisioner: $1
parameters:
  server: $server_name
  share: $nfs_share
reclaimPolicy: Delete
volumeBindingMode: Immediate
mountOptions:
  - nfsvers=4.1
EOF
}

# find multi attached volume
for i in $volumes
    do number=$(cat $CLEANED | yq eval -o json | jq --arg i $i -r '.services|to_entries[]|.value|select(has("volumes"))|.volumes[]|=select((.type)=="volume")| {(.container_name): (.volumes[]|select(.type=="volume"))}|to_entries[]|select(.value.source==$i).key'|wc -l)
     if test $number -gt 1
        then blue "There are multi attachments for \"$i\" volume"
             echo "A RWX csi driver is required for multi-attachments PVC"
            if [[ -n "$nfs_csi" ]]
                then
                    echo "\"$nfs_csi\" driver is installed to this k8s cluster"
                    if [[ -n $nfs_sc ]];
                        then 
                            echo "There is an existing storage class $nfs_sc that points to"
                            oc get sc -o json | jq --arg nfs_csi $nfs_csi -r '.items[]|select(.provisioner|test("\($nfs_csi)"))|(.parameters.server + ":" + .parameters.share)'
                        else
                            read -p "$(italics "?? Do you want to create a nfs storage class using \"nfs.csi.k8s.io\" driver?.........:$(faint "[y]") ")" yn
                            yn=${yn:-y}
                            case $yn in
                                [Yy]* )
                                    create_sc nfs.csi.k8s.io
                                    ;;
                                [Nn]* )
                                    echo "$new_i PVC will be installed by the default \"ovirt-csi\" stotage class in RWO mode, some container may not start because of this."
                                    ;;
                            esac
                    fi
                else
                    while true; do
                        read -p "$(italics "?? Do you want to install the \"nfs.csi.k8s.io\" driver?(y/n)...............:$(faint "[y]") ")" yn
                        yn=${yn:-y}
                        case $yn in
                            [Yy]* )
                                echo "Downloading and installing nfs.csi.k8s.io driver to cluster"
                                curl -skSL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/v4.7.0/deploy/install-driver.sh | bash -s v4.7.0 --
                            read -p "$(italics "?? Do you want to create a nfs storage class using nfs.csi.k8s.io driver?.........:$(faint "[y]") ")" yn
                            yn=${yn:-y}
                            case $yn in
                                [Yy]* )
                                    create_sc nfs.csi.k8s.io
                                    ;;
                                [Nn]* )
                                    echo "$new_i PVC will be installed by the default \"ovirt-csi\" stotage class in RWO mode, some container may not start because of this."
                                    ;;
                            esac
                                break;;
                            [Nn]* )
                                echo "$new_i PVC will be installed by the default \"ovirt-csi\" stotage class in RWO mode, some container may not start because of this."
                                ;;
                        esac
                    done
            fi
            while true; do
                read -p "$(italics "?? Do you want to use \"nfs-csi\" storage class for \"$i\" volume? (y/n)....................................:$(faint "[y]") ")" yn
                yn=${yn:-y}
                case $yn in
                    [Yy]* )
                        new_i=$(echo $i | sed 's/\./-/g' |sed 's/_/-/g')
                        echo "patching nfs-csi in $new_i-persistentvolumeclaim.yaml......................................."
                        cat $new_i-persistentvolumeclaim.yaml | yq -o json |jq  '.spec.storageClassName="nfs-csi"|.spec.accessModes=["ReadWriteMany"]' | yq -P | sponge $new_i-persistentvolumeclaim.yaml
            			break;;
                    [Nn]* )
                        echo "$new_i PVC will be installed by the default \"ovirt-csi\" stotage class in RWO mode, some container may not start because of this."
                        ;;
                esac
            done
     fi 
	done


#Calcul des tailles des disques persistants
copy_to_okd () {
if [[ $1 = "bind" ]]
	then
		SOURCES=$(cat $NAME.yml | yq -ojson | jq -r --arg type $1 --arg DIR "${PWD##*/}" '(.services[].volumes[]?|select(.type=="\($type)")|select(.source|test("home|root")))|={source: .source|split("\($DIR)")|.[1], type: .type, target: .target}|del (.services[].volumes[]?|select(.source|test("sock")))| del (.services[].volumes[]?|select(.source|test("/applis")))|.services|to_entries[]|{sources: (.key + ":." + (.value|select(has("volumes")).volumes[]|select(.type=="\($type)")|select(.source!=null)|select(.source|test("(\\.[^.]+)$")|not)|.source))}|.sources')
	else
		SOURCES=$(cat $NAME.yml | yq -ojson | jq -r --arg type $1 '(.services[].volumes[]?|select(.type=="\($type)")|select(.source|test("home|root")))|={source: .source, type: .type, target: .target}|del (.services[].volumes[]?|select(.source|test("sock")))| del (.services[].volumes[]?|select(.source|test("/applis")))|.services|to_entries[]|{sources: (.key + ":" + (.value|select(has("volumes")).volumes[]|select(.type=="\($type)")|select(.source!=null)|select(.source|test("(\\.[^.]+)$")|not)|.source))}|.sources')
fi
if [ -n "$SOURCES" ]
	then 
		echo -e "Here are available ${1}s:"
		blue "$SOURCES\n"
		# exit 1
		index=0
		declare -a tab1
		declare -a tab2
		declare -a tab3
		declare -a tab4
		calc(){ awk "BEGIN { print $*}"; }
		for i in $SOURCES; 
			do 
				SVC=$(echo $i | cut -d':' -f1)
				SRC=$(echo $i | cut -d':' -f2)
				SRC_orig=$(echo $SRC|sed 's/-/\./g')
				index=$(($index + 1))

				if [[ $1 = "volume" ]]
					then 
						src="/var/lib/docker/volumes/${NAME}-docker_${SRC_orig}/_data/"
				elif [[  $(echo $SRC |grep "./") != '' ]]
					then
						src="/opt/pod/${NAME}-docker/${SRC}"
				else
					src=$SRC
				fi

				echo "Calculating required size for disk claiming from $docker_host......................." 
				tab1[$index]=$(ssh root@${docker_host} du -s $src | cut -f1) 
				echo "$SRC"
				echo "$SVC:$(blue ${tab1[$index]})"
				if [[ ${tab1[$index]} -lt "100000" ]];
					then
						tab2[$index]="100Mi"
					else
						tab2[$index]=$(echo $(calc "int(${tab1[$index]} / (1024*1024) +1)+1")Gi)
				fi

				echo "$SVC:$(blue ${tab2[$index]})"
				tab3[$index]=$(cat $NAME.yml | yq eval -ojson| jq -r --arg size "${tab2[$index]}" --arg svc "$SVC" --arg src "$SRC" '.services |to_entries[] | select(.value.volumes | to_entries[] |.value.source | test("\($src)$"))?|select(.key=="\($svc)")|.value.volumes|=map(select(.source|test("\($src)$"))|with_entries(select(.key="source"))|.source="\($src)"|.size="\($size)")'|jq -s '.[0]|del(..|nulls)')
				echo -e "\n"
			done

		length=$(echo "${tab3[*]}" | jq -s 'length')
		for ((i=0; i<$length; i++ ))
			do
				tab4[$i]=$(echo "${tab3[*]}" | jq -s --arg i "$i" '.[$i|tonumber]')
			done		

		for i in "${tab4[@]}"; do
		if [ "$i" != "null" ]; then
			templist+=( "$i" )
		fi
		done

		volumes=("${templist[@]}")
		index=0
		mount_points=$(echo $nfs_mount_points | jq -rs '.[]|.mount_point|split("/")|last')

		select_nfs_mount_point() {
				toto=$(echo "$i" |jq -r '.value.volumes[].source|split("/")|last')
					for j in $mount_points
						do 
							echo "$toto" | grep "$j" > /dev/null
							if [ "$?" == "0" ]
								then 
									mount_point=$(echo $nfs_mount_points |jq -rs --arg j "$j" '.[]|select(.mount_point|test("\($j)")).mount_point|split("/")|last')
							fi
						done
		}

		# Change size of volumeclaim yaml declaration
		for i in "${volumes[@]}"; 
			do 
				select_nfs_mount_point
				size=$(echo $i | jq -r '.value.volumes[]?.size'|uniq)
				source=$(echo $i | jq -r '.value.volumes[]?.source'|uniq)
				service=$(echo $i | jq -r '.key'|uniq)
				if [ "$mount_point" != "${source##*/}" ] ; then
					for j in $(echo $i | jq -r --arg service "$service" 'select(.key=="\($service)").value.volumes[].target')
						do 
							index=$(echo "${volumes[*]}" |jq -s --arg j "$j" --arg service "$service" '[group_by(.key)[]|.[]|select(.key=="\($service)").value.volumes[0]]|[.[].target]|index("\($j)")')
							if [[ $1 = "bind" ]]
								then
									file="${service}-claim${index}-persistentvolumeclaim.yaml"
									file_name="${service}-claim${index}"
								else
									file="${source}-persistentvolumeclaim.yaml"
									file_name="${source}"
							fi

							status=""
							search_pvc=$(oc get pvc -o json | jq --arg file_name $file_name '.items[]|.metadata|select(.name=="\($file_name)")')
							if [ -n "$search_pvc" ]
								then
									while [ "$status" != "Bound" ] && [ -n "$file_name" ]
										do
											echo "Waiting for pvc to be ready...."
											status=$(oc get pvc $file_name -o json | jq -r '.status.phase')
											sleep 5
										done

									is_nfs=$(oc get pvc $file_name -o json | jq -r '.spec.storageClassName|test("nfs")')
									if [[ $is_nfs != "true" ]]
										then
											echo "Resizing $file_name to $size ................"
											cat ${file} | 
												yq eval -ojson| 
												jq --arg size "$size" '.spec.resources.requests.storage=$size'| 
												yq eval -P |
											sponge ${file}
											oc apply -f ${file}
											echo ""
									fi
							fi
						done
				fi
			done

		read -p "$(italics "?? Would you like to copy current data to okd volume of type $1 (may be long)? (y/n).......................................$(faint "[y]")")" answer
		answer=${answer:-y}
		private_key=$(cat ~/.ssh/${key:-id_rsa})
		if [[ "$answer" = "y" ]];
			then
				for i in "${volumes[@]}"; 
					do 
						select_nfs_mount_point
						service=$(echo $i | jq -r '.key')
						target=$(echo $i | jq -r '.value.volumes|last.target')
						source=$(echo $i | jq -r '.value.volumes|last.source')

						if [ "$mount_point" != "${source##*/}" ]; then
							if [[ "$(echo $source| grep backup)" != '' ]];
								then
									src=$source
								else
									if [[ $1 = "bind" ]]
										then
											src="/opt/pod/${NAME}-docker/${source}"
										else
											src="/var/lib/docker/volumes/${NAME}-docker_${source}/_data/"
									fi
							fi
							size=$(echo $i | jq -r '.value.volumes[].size')
							echo "###########################################################################"
							echo -e "$service:\nPaste those commands to copy data:"
							echo -e "${YELLOW}from${ENDCOLOR} ${docker_host}:${src}/ ${YELLOW}to${ENDCOLOR} persistent volume ($size):\n"
							blue "mkdir /root/.ssh && echo \"$private_key\" > /root/.ssh/id_rsa && chmod 600 -R /root/.ssh; \
if [ \"\$(cat /etc/os-release|grep "alpine")\" = '' ]; \
then apt update && apt install rsync openssh-client -y;  \
else apk update && apk -f add rsync openssh-client-default openssh-client; fi; \
rsync -av -e 'ssh -o StrictHostKeyChecking=no' ${docker_host}:${src}/ ${target}/; \
exit"
							echo "###########################################################################"
							POD=$(oc get pods -o json| jq -r --arg service "$service" '.items[]|.metadata|select(.name|test("\($service)-[b-df24-9]+-[b-df-hj-np-tv-z24-9]{5}"))|.name')
							oc debug $POD --as-root=true
						fi
					done
		fi
	else
		blue "No volume of type \"$1\"...... going on"
fi
}

release_pv() {
	for i in $(oc get pv -ojson | jq -r --arg NAME "$1" '.items[].metadata|select( (.name|test("\($NAME)")) and (.name|test("nfs")) ).name')
		do
			echo -e "Releasing pv applis-$i..........................................................\n"
			oc patch pv $i -p '{"spec":{"claimRef": null}}'
		done
}

step "4" " Application deployment"
choice=$(
case $ENV in
	local) echo -e "oc apply -f \"*.yaml\"\n";;
	*) echo -e "cd $NAME-docker-$ENV && \'oc apply -f \"*.yaml\"\'\n";;
esac
)

read -p "$(italics "?? Would you like to deploy $NAME on OKD $ENV?.......................................$(faint "[y]") ")" answer
answer=${answer:-y}
echo -e "(You can alternatively do it later by manually entering: $choice)"

if [[ "$answer" == "y" ]]; 
	then
		OKD=$(oc project 2>&1 >/dev/null)
		echo $OKD
		if [[ $(echo $OKD| grep "Unauthorized") != '' ]]
			then
				echo "First connect to your OKD cluster with \"export KUBECONFIG=path_to_kubeconfig\" and reexecute the script..........................."
				exit 1
			else
				release_pv $NAME
				while true; do
					read -p "$(italics "?? Would you like to create a new project? (y/n)....................................$(faint "[y]")"): " yn
					yn=${yn:-y}
					case $yn in
						[Yy]* )                         
							read -p "$(italics "?? Enter the name of the project $(faint "[$namespace]")....................................:") " project
							project=${project:-$namespace}
							oc new-project $project
							echo -e "Setting SCC anyuid to default SA.......................................\n"
							oc adm policy add-scc-to-user anyuid -z default
							read -p "$(italics "?? Do you want to authenticate against DockerHub? $(faint "[n]")"): " ynyn
							ynyn=${ynyn:-n}
							case $ynyn in
								[Yy]* ) 
									read -p "$(italics "?? DockerHub server $(faint "[docker.io]")"): " dh_server
									dh_server=${dh_server:-docker.io}
									read -p "$(italics "?? DockerHub username" ): " dh_user
									read -p "$(italics "?? DockerHub password" ): " dh_passwd
									echo -e "Creation of docker secret for pulling images without restriction.......................................\n"
									oc create secret docker-registry docker.io --docker-server=${dh_server} --docker-username=${dh_user} --docker-password=${dh_passwd}
									oc secrets link default docker.io --for=pull
									echo -e "\n"
									;;
							esac

							break;;
						[Nn]* )
							break;;
						* ) echo "Please answer yes or no.";;
					esac
				done

				read -p "$(italics "?? Ready to deploy $name. Press \"Enter\" to begin.......................................")" answer
				oc apply -f "*.yaml*"
				echo -e "\n"
				oc get pods
				echo -e "\n"
				step "5" "Copy of persistent volumes"
				title "5.1" "Copy data to pvc of type bind"
				copy_to_okd bind
				title "5.2" "Copy data to pvc of type volume"
				copy_to_okd volume
				echo -e "\n"
		fi
	else
		step "5" "Copy of persistent volumes"
		title "5.1" "Copy data to pvc of type bind"
		copy_to_okd bind
		title "5.2" "Copy data to pvc of type volume"
		copy_to_okd volume
fi


# Redémarrage des pods et URL de connexion

step "FINAL" "Pods reload and connexion URL"
read -p "$(italics "?? Reloading pods to launch \"$NAME\" $(faint "[y]") : ?")" yn
yn=${yn:-y}
case $yn in
	[Yy]* )    
		echo "Restart all $NAME pods......................................." 
		oc rollout restart deploy
		timeout 10 oc get pods -w;;
	[Nn]* )
		echo "You should manually relaod pods before \"$NAME\" being up by typing \"oc rollout restart deploy\"";;
esac

echo -e "\n Here is the list of configured services: \n"
oc get svc
read -p "$(italics "?? Enter a list of above services you want to expose: ")" services
for i in $services
	do
		oc expose svc $i
	done
	
URL=$(oc get route -o json | jq  -r '[.items[]|.spec]|first|.host')
title "###" "Congratulations!"
echo -e "You can reach $NAME application at: "
blue "http://$URL\n"





