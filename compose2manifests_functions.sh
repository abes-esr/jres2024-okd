#!/bin/bash
# 24/10/21 blanchet<at>abes.fr
# Script de conversion d'un fichier docker-compose.yaml en manifests k8s
# Génère pour chacun des services ces manifest: deploy, services, configMap, secret, persistentVolumeClaim
# Nécessite les paquets jq, yq, jc, moreutils, docker-compose, kompose
# Usage:
# ./compose2manifests.sh [ prod || test || dev || local ] [ appli_name ] [default || '' || secret || env_file | help] [kompose] [helm]\n"

source functions.sh

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


for i in jq yq docker-compose kompose oc jc; do install_bin $i; done

echo -ne "Application to deploy: " 
blue \"$NAME\"
namespace=$(oc config view --minify -o 'jsonpath={..namespace}')
api=$(oc config view --minify -o 'jsonpath={..server}')
echo -ne "Cluster k8s: "
blue $api
echo -ne "Namespace in use: "
blue "\"$namespace\""
echo -e "A video usecase is available at: https://vimeo.com/1022133270/90cfd9e0a7\n" 

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


# Check ssh key presence 
set_ssh_key

# Docker hosts domain identification
dom=$(hostname -d)
read -p "$(italics "?? Please enter the domain (default is the one of the bastion) $(faint [$dom]): ")" domain2
domain=${domain:-$dom}
blue $domain

echo ""


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
		title "2.4" "Declaration of \${services}.env into deployments"
		for i in $(cat $CLEANED|yq eval -ojson|jq -r --arg var "$i" '.services|to_entries|map(select(.value.environment != null)|.key)|flatten[]'); \
			do echo $i; cat $CLEANED | \
						yq eval - -o json | \
						jq -r  --arg var "$i" '.services[$var]."env_file" = $var +".env"' | \
						sponge $CLEANED ; \
			done
		message

	# Suppression des environnements et nettoyage final
	title "2.5" "Cleaning"
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





