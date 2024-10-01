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
	echo -e "env_file: \t\tGenerates cleaned advanced appli.yml with migrating pflain 'environment' \n\t\t\tto 'env_file' statement, will be converted into k8s configmaps"
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
echo "1> Nettoyage........................................"
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
                        BIN="kubernetes/kompose/releases/download/v1.28.0/kompose-linux-amd64";;
				oc)
						wget -q okd-project/okd/releases/download/4.12.0-0.okd-2023-02-18-033438/openshift-client-linux-4.12.0-0.okd-2023-02-18-033438.tar.gz \
							 -O /usr/local/bin/ | \
						tar xzf -
						chmod +x {kubectl,oc};;
                *)
                ;;
        esac
        echo "Installing $1......................................."
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
          *) $1 version;;
  esac
}

for i in jq yq docker-compose kompose oc; do install_bin $i; done

echo -e "\n"

echo "ETAPE 3: Téléchargement du docker-compose"

if [[ "$1" == "prod" ]] || [[ "$1" == "test" ]] || [[ "$1" == "dev" ]]; then
		echo "##### Avertissement! #######################"
		echo "Il faut que clé ssh valide sur tous les comptes root des diplotaxis{}-${1} pour continuer......................................."
		read -p "Continuer? (y/n)...........[y]" continue
		continue=${continue:-y}
		if [[ "$continue" != "y" ]]; then 
			echo "Please re-execute the script after having installed your ssh pub keys on diplotaxis{}-${1}"
			exit 1;
		fi
		echo "Ok, let's go on!"
		diplo=$(for i in {1..6}; \
		do ssh root@diplotaxis$i-${1}.v106.abes.fr docker ps --format json | jq --arg toto "diplotaxis${i}-${1}" '{diplotaxis: ($toto), nom: .Names}'; \
		done \
		| jq -rs --arg var "$2" '[.[] | select(.nom | test("^\($var)-.*"))]|first|.diplotaxis'); \
		echo -e "$NAME is running on $diplo\n"
		mkdir $2-docker-${1} && cd $2-docker-${1}; \
		echo "Getting docker-compose.file from GitHub.......................................";  \
		wget -N https://raw.githubusercontent.com/abes-esr/$2-docker/develop/docker-compose.yml 2> /dev/null; \
		echo $PWD; \
		rsync -av root@$diplo.v106.abes.fr:/opt/pod/$2-docker/.env .; \
elif [[ "$1" == local ]];then
		echo "Enter a diplotaxis name"
		read diplo
		if ! [[ -f ./docker-compose.yml ]]; then
			echo "If $2 is hosted on gitlab.abes.fr, you can download your docker-compose.yml (y/n).......................................?"
			read rep
			if [[ "$rep" == "y" ]];then
				echo "Please provide your gitlab private token (leave empty if public repo)......................................."
				read token
				ID=$(curl -s --header "PRIVATE-TOKEN: $token" https://git.abes.fr/api/v4/projects | \
				jq -r --arg toto "$2" '.[] | select(.name==$toto)| .id')
				curl -s --header "PRIVATE-TOKEN: $token" https://git.abes.fr/api/v4/projects/${ID}/repository/files/docker-compose.yml/raw?ref=main > docker-compose.yml
				vi docker-compose.yml
				if ! [[ -f ./.env ]];then
					echo "Please manually provide a valid \".env\" file in the same directory as docker-compose.yml file ($pwd)"
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

echo -e "\n"
# Customizing .env
if test -f .env; 
	then
		read -p "Do you want to customize your variable environment before the conversion to manifests?: "[y]
		yn=${yn:-y}
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

echo "\n"
echo "2> Définition du nom du projet"
# NAME=$(cat docker-compose.yml | yq eval -o json | jq -r '[.services[]]| .[0].container_name' | cut -d'-' -f1)
NAME=$2
echo -e "projet: $NAME\n"

echo "############################################"

echo "ETAPE 3: Conversion du  en manifests Kubernetes"

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
docker-compose config | sed 's/\.svc//g'> $NAME.yml
message
# 2> Conversion initiale du docker-compose.yml
echo -e "2> #################### Conversion initiale du $NAME.yml ####################\n"
docker-compose -f $NAME.yml convert --format json \
| jq 'del(..|nulls)' \
| jq --arg toto "$NAME" 'del (.services."\($toto)-watchtower")' \
| jq 'del(.services[].volumes[]?|select(.source|test("sock")))' \
| jq 'del (.services[]."depends_on")' \
| jq 'del (.services."theses-elasticsearch-setupcerts")' \
| jq 'del (.services."theses-elasticsearch-setupusers")' \
| jq 'del (.services."theses-api-diffusion-poc")' \
| jq 'del (.services[].mem_limit)'\
| jq '.volumes|=with_entries(.key|=gsub("\\.";"-"))' \
| jq '.services[].volumes[]?|=(if .type=="bind" then . else .source|=gsub("\\.";"-") end)' \
| jq '.services|=with_entries(.value|=(select(has("volumes")).volumes |= sort_by((.type)) ))' \
| docker-compose -f - convert | sponge $NAME.yml

message
echo -e "\n"

#### NBT 231108
#### insertion de la clé "secrets" dans chacun des services de docker-compose.yml
#### prend en paramètre le nom du fichier docker-compose.yml

CLEANED="$NAME.yml"

if [ -n "$3" ]; then
		echo -e "on continue......................................."
	if [ "$3" == 'secret' ] || [ "$3" == 'env_file' ]; then

		if [ "$3" = "secret" ]; then

			######  transformation du docker-compose.yml en liste réduite ######
			# SMALL_LIST=$(cat $CLEANED | yq eval - -o json | jq '[.services[]|  {(.container_name): .environment}]') 
			SMALL_LIST=$(cat $CLEANED | yq eval - -o json | jq '.services|to_entries[] | {(.key): .value.environment}'| jq -s)
			#echo $SMALL_LIST| yq eval -P
			message

			###### select variable name filtering by KEY or PASSWORD ####
			FILTER_LIST=$(echo $SMALL_LIST | yq eval - -o json \
							| jq '.[]|to_entries[]|try {key:.key,value:.value|to_entries[]} | select(.value.key | test("KEY|PASS|SECRET"))' \
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
				cat $CLEANED | yq eval - -o json| jq --arg toto "$service" --arg tata "$KEY" '.services[$toto].secrets |= . + [$tata|ascii_downcase|gsub("_";"-")]' \
					| yq eval - -P | sponge $CLEANED; \
				done
			message
		
			###### Generating secret files from .env file  #####
			export var=$(echo $FILTER_LIST | jq  -r '.[].value.key') \
			# export data=$(echo $FILTER_LIST | jq  -r '.[].value.value') \
			for i in $(echo $var); \
			do export data=$(echo $FILTER_LIST | jq --arg tata "$i" -r '[.[].value | select(.key==$tata).value]|first')
				echo $data > $(echo $i| sed 's/_/-/g' | tr '[:upper:]' '[:lower:]').txt; \
				cat $CLEANED \
				| yq eval - -o json \
				| jq --arg toto $i '.secrets[$toto|ascii_downcase|gsub("_";"-")].file = ($toto|ascii_downcase|gsub("_";"-")) + ".txt"' \
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
				# egrep -v 'KEY|PASSWORD' | \
				yq eval - -P| \
				sed "s/:\ /=/g" > $i.env; 
			done
		message

		# 4> Déclaration des variables contenant un secret dans le env_file
		for i in $(ls *.env); 
			do 
				for j in $(cat $i | egrep '(KEY|PASS|SECRET)'); 
					do 
						KEY=$(echo $j | cut -d"=" -f1);
						LINE=$(echo $KEY | cut -d"=" -f1 | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g');
						sed -i "s/.*$KEY.*/$KEY=\/run\/secrets\/$LINE/g" $i;
					done; 
			done 

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

# cat $CLEANED
echo -e "\n"
    
# Patch ReadOnlyMany pvc to ReadWriteOnly. The readOnly feature will be later executed with the "readOnly:"" true directive into deployment
patch_RWO () {
for i in $(grep ReadOnlyMany *persistent* |cut -d: -f1); 
	do 
		echo "Patching \n ReadOnlyMany modeAccess to ReadWriteOnce in $i......................................." 
		sed -i 's/ReadOnlyMany/ReadWriteOnce/g' $i; 
	done
}

patch_expose_auto () {
    # services=$(docker-compose -f $CLEANED config | yq -o json| jq -r '.services|to_entries[]|.value|select((has("ports") or has("expose"))|not)?|."container_name"')
    # if [[ -n $services ]]
    #     then
			for service in $services; 
				do 
					port=$(ssh root@$diplo docker inspect $service | jq -cr '[.[].NetworkSettings.Ports|to_entries[]|.key|split("/")|.[0]'])
                    port=${port:-[]}
                    if [[ $port != '[]' ]]
                        then
                            echo "Patching ports $port for service $service ............"
                            cat $CLEANED | yq -o json | jq --arg service "$service" --argjson port "$port" '.services."\($service)".expose+=$port' \
                            |sponge $CLEANED
                    fi
				done
			cat $CLEANED | yq -P | sponge $CLEANED
	# fi
}

patch_expose () {
    # services=$(docker-compose -f $CLEANED config | yq -o json| jq -r '.services|to_entries[]|.value|select((has("ports") or has("expose"))|not)?|."container_name"')
    # if [[ -n $services ]]
    #     then
    #         echo -e "The following services don't have any explicit defined ports: \n$services"
            echo "You may define them one by one so as the conversion to be successfull"
            for service in $services; 
                do 
                    read -p "$service: Enter port number to expose the service (press to leave empty): " port
                    # port=${port:-[]}
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
	# fi
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
	echo "patching ingress in $NAME-docker-$1-default-networkpolicy.yaml......................................."
	if [[ $1 != "local" ]]
		then 
			NETWORK=$NAME-docker-$1-default-networkpolicy.yaml
		else
			NETWORK=okd-default-networkpolicy.yaml
	fi
	cat $NETWORK | 
		yq eval -ojson | 
		jq '.spec.ingress|=
				map(.from |= .+ [{"namespaceSelector":{"matchLabels":{ "policy-group.network.openshift.io/ingress": ""}}}])'|
		yq eval -P | sponge $NAME-docker-$1-default-networkpolicy.yaml
}

# Patch pvc pour /appli
patch_pvc () {
	index="-1"
	for i in $applis_svc; 
		do 
			index=$(cat $NAME.yml | yq eval -ojson | jq -r  --arg applis_svc "$i" '.services|to_entries[]| [{services: .key, volumes: .value.volumes[]|select(.source|test("/appli"))}]?|to_entries[]|select(.value.services=="\($applis_svc)").key')
			for j in $(echo $index);
				do
					echo "patching /applis in $i-claim$j-persistentvolumeclaim.yaml ......................................."
					cat $i-claim$j-persistentvolumeclaim.yaml | 
						yq eval -ojson | 
							jq --arg name "$i" --arg env "$1" --arg index "$j" '.spec.resources.requests.storage="8Ti"|.spec.volumeName="applis-\($name)-\($env)-\($index)"|.spec.storageClassName=""|.spec.accessModes=["ReadWriteMany"]' |
						yq eval -P | sponge $i-claim$j-persistentvolumeclaim.yaml
				done
		done
}

create_pv_applis () {
	if [[ $applis_svc != '' ]];
		then
			for i in $applis_svc;
				do 
					index="-1"
					applis_source=$(cat $NAME.yml | yq eval -ojson | \
													jq -r --arg applis_svc "$i" '.services|to_entries[]|select(.key=="\($applis_svc)")|.value.volumes[].source|split("/applis/")|.[1]'|uniq)
					for j in $applis_source; 
						do
							index=$((index +1))
							echo "creating $i-pv$index-persistentvolume.yaml ......................................."
echo "apiVersion: v1
kind: PersistentVolume
metadata:
  name: applis-$i-$1-$index
spec:
  capacity:
    storage: 8Ti 
  accessModes:
  - ReadWriteMany
  nfs: 
    path: /mnt/EREBUS/zpool_data/$j
    server: erebus.v102.abes.fr 
  persistentVolumeReclaimPolicy: Retain" > $i-pv$index-persistentvolume.yaml
						done
				done
	fi
}

patch_configmaps() {

	 for i in $(ls | grep "deployment")
	 	do 
			echo "patching configMaps in $i ......................................."
			claims=$(cat $i | yq -ojson| jq -r '.spec.template.spec.containers[].volumeMounts[]?|select((.mountPath|test("(\\.[^.]+)$")) and (.name|test("claim"))).name')
			# echo $claims

			for j in $claims
				do 
					echo "deleting ${j}-persistentvolumeclaim.yaml ......................................."
			        rm -f ${j}-persistentvolumeclaim.yaml
					cat $i | yq -ojson| \
					jq -r --arg j $j 'del(.spec.template.spec.volumes[]?|(select(.name=="\($j)")))'| \
					sponge $i
				done
			# cat $i

			services=$(cat $i | yq -ojson| jq -r '.spec.template.spec.containers[].volumeMounts[]?|select((.mountPath|test("(\\.[^.]+)$")) and (.name|test("claim")))|(.name|split("-claim")|.[0]) + "-" + (.mountPath|split("/")|last|gsub("_";"-")|gsub("\\.";"-")|ascii_downcase)')
			# echo $services

			for j in $services
				do cat $i | yq -ojson| \
					jq -r --arg j $j '((.spec.template.spec.containers[].volumeMounts[]?|select((.mountPath|test("(\\.[^.]+)$")) and (.name|test("claim")) )) |= {mountPath: .mountPath, name: ((.name|split("-claim")|.[0]) + "-" + (.mountPath|split("/")|last|gsub("_";"-")|gsub("\\.";"-")|ascii_downcase)), subPath: (.mountPath|split("/")|last)})|.spec.template.spec.volumes+=[{configMap: {defaultMode: 420, name: $j}, name: $j}]' | \
					sponge $i 
				done 
			# cat $i | yq -P
			# exit 1
		done
}

patch_configmaps_new () {
for i in $(cat movies.yml | yq -ojson| jq -r '.services|keys[]')
    do 
        sources=$( cat movies.yml | yq -ojson| jq -r  --arg i $i '.services|to_entries[]|select(.key=="\($i)").value.volumes[]?|.source|split("/")|last' )
        # echo $sources
        for j in $sources
            do
                echo -e "patching ${i}-deployment.yaml with source $j......."
                cat ${i}-deployment.yaml | yq -ojson | \
                jq -r --arg i $i --arg j $j '((.spec.template.spec.containers[].volumeMounts[]?|select((.mountPath|test("(\\.[^.]+)$")) and (.name|test("claim")) )) |= {mountPath: .mountPath, name: ("\($i)-" + $j|gsub("_";"-")|gsub("\\.";"-")|ascii_downcase), subPath: $j })|.spec.template.spec.volumes+=[{configMap: {defaultMode: 420, name: ("\($i)-" + $j|gsub("_";"-")|gsub("\\.";"-")|ascii_downcase)}, name: ("\($i)-" + $j|gsub("_";"-")|gsub("\\.";"-")|ascii_downcase)}]' | yq -P | \
                sponge ${i}-deployment.yaml 
            done
    done
}

create_configmaps() {
	# echo "ETAPE 2: Création des object configMaps pour les volumes bind qui sont des fichiers et non des répertoires"

	CM=$(cat $NAME.yml | yq -o json | jq -r --arg pwd "$NAME-docker-$1" '.services[].volumes|select(.!=null)|.[]|select(.type == "bind")|select(.source|test("(\\.[^.]+)$"))|select(.source|test("sock")|not).source|split($pwd)|.[1]?')
	# CM_RENAMED=$(cat $NAME.yml | yq -o json | jq -r --arg pwd "$NAME-docker-$1" '.services|to_entries[]|{name: .key, volumes: (.value|.volumes|select(.!=null)|.[]|select(.type == "bind")|select(.source|test("(\\.[^.]+)$"))|select(.source|test("sock")|not).source|split($pwd)|.[1])}|(.name + "-" + (.volumes|split("/")|last|gsub("\\/";"-")|gsub("\\.";"-")|gsub("\\_";"-")|ascii_downcase))')
	CM_RENAMED=$(cat $NAME.yml | yq -o json | jq -r --arg pwd "$NAME-docker-$1" '.services|to_entries[]|{name: .key, volumes: (.value|.volumes|select(.!=null)|.[]|select(.type == "bind")|select(.target|test("(\\.[^.]+)$"))|select(.target|test("sock")|not).target|split("/")|last)}|(.name + "-" + (.volumes|split("/")|last|gsub("\\/";"-")|gsub("\\.";"-")|gsub("\\_";"-")|ascii_downcase))')
	CM_RENAMED_short=$(cat $NAME.yml | yq -o json | jq -r --arg pwd "$NAME-docker-$1" '.services|to_entries[]|{name: .key, volumes: (.value|.volumes|select(.!=null)|.[]|select(.type == "bind")|select(.target|test("(\\.[^.]+)$"))|select(.target|test("sock")|not).target|split("/")|last)}|((.volumes|split("/")|last))')


	declare -a tab_CM
	declare -a tab_CM_RENAMED
	declare -a tab_CM_RENAMED_short

	index=-1
	for i in $CM 
		do 
			index=$(($index + 1))
			tab_CM[$index]=$i
		done 
	# echo ${tab_CM[@]}

	index=-1
	for i in $CM_RENAMED
		do 
			index=$(($index + 1))
			tab_CM_RENAMED[$index]=$i
		done 
	# echo ${tab_CM_RENAMED[@]}

	index=-1
	for i in $CM_RENAMED_short
		do 
			index=$(($index + 1))
			tab_CM_RENAMED_short[$index]=$i
		done 
	# echo ${tab_CM_RENAMED[@]}


	if [[ ! -d './volumes' ]]; 
		then
			mkdir volumes
	fi

	sshfs root@$diplo.v106.abes.fr:/opt/pod/$NAME-docker/ ./volumes/

	for ((i=0; i<=$index; i++ ))
		do 
			echo "creating configMap file ${tab_CM_RENAMED[$i]}-configmap.yaml ......................................."
			oc create cm ${tab_CM_RENAMED[$i]} --from-file=./volumes/${tab_CM[$i]} --dry-run=client -o json  | jq -r --arg z  "${tab_CM_RENAMED_short[$i]}" '(if has("data") then .data|=with_entries(.key="\($z)") else .binaryData|=with_entries(.key="\($z)") end)' | yq -P > ${tab_CM_RENAMED[$i]}-configmap.yaml
		done

	fusermount -u volumes

	# echo "############################################"
}


# 7> génération des manifests
echo -e "7>#################### Génération des manifests ###################\n"

services=$(cat $CLEANED | yq -o json| jq -r '.services|to_entries[]|.value|select((has("ports") or has("expose"))|not)?|."container_name"')
if [[ -n $services ]]
	then
		echo -e "The following services don't have any explicit defined ports: \n$services"
		read -p "Do you want to fetch ports from existing docker containers on $diplo : [y]" yn
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

applis_svc=$(cat $NAME.yml | yq eval -ojson | \
	jq -r '.services|to_entries[]| [{services: .key, volumes: .value.volumes[]|select(.source|test("/appli"))}]?|.[].services'|uniq)
applis_source=$(cat $NAME.yml | yq eval -ojson | \
    jq -r '.services|to_entries[]| [{services: .key, volumes: .value.volumes[]|select(.source|test("/appli"))}]?|.[].volumes.source')
if [ -n "$4" ] && [ "$4" = "kompose" ]; then
	echo -e "6> #################### génération des manifests ####################\n"
	if [ -n "$5" ] && [ "$5" = "helm" ]; then  
		kompose -f $CLEANED convert -c
		cd $NAME/templates
	else
		kompose -f $CLEANED convert
	fi
	patch_RWO
	patch_secret
	patch_secretKeys
	patch_networkPolicy $1
	create_pv_applis $1
	patch_pvc $1
	patch_configmaps $CLEANED
	create_configmaps $1
fi

echo -e "6>#################### Patch multi-attached volumes ###################\n"

# find targeted volumes 
export volumes=$(cat $CLEANED | yq eval -o json | jq -r '.services|to_entries[]|.value|select(has("volumes"))|.volumes[]|select((.type)=="volume").source'|uniq)

# find if there is a nfs csi driver installed on the cluster
export nfs_csi=$(oc get csidrivers.storage.k8s.io -o json | jq -r '.items[].metadata|select(.name|test("nfs")).name')
export nfs_sc=$(oc get sc -o json | jq --arg nfs_csi $nfs_csi -r '.items[]|select(.provisioner|test("\($nfs_csi)")).metadata.name')

create_sc() {
    read -p "Enter NFS server name [methana.v102.abes.fr]...........: " server_name
    server_name=${server_name:-methana.v102.abes.fr}
    read -p "Enter NFS share [/pool_SAS_2/OKD]............: " nfs_share
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
        then echo "There is multi attachments for \"$i\" volume"
             echo "A RWX csi driver is needed for multi-attachments PVC"
            if [[ -n "$nfs_csi" ]]
                then
                    echo "\"$nfs_csi\" driver is installed to this k8s cluster"
                    if [[ -n $nfs_sc ]];
                        then 
                            echo "There is an existing storage class $nfs_sc that points to"
                            oc get sc -o json | jq --arg nfs_csi $nfs_csi -r '.items[]|select(.provisioner|test("\($nfs_csi)"))|(.parameters.server + ":" + .parameters.share)'
                        else
                            read -p "Do you want to create a nfs storage class using \"nfs.csi.k8s.io\" driver?.........:[y] " yn
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
                        read -p "Do you want to install the \"nfs.csi.k8s.io\" driver?(y/n)...............:[y] " yn
                        yn=${yn:-y}
                        case $yn in
                            [Yy]* )
                                echo "Downloading and installing nfs.csi.k8s.io driver to cluster"
                                curl -skSL https://raw.githubusercontent.com/kubernetes-csi/csi-driver-nfs/v4.7.0/deploy/install-driver.sh | bash -s v4.7.0 --
                            read -p "Do you want to create a nfs storage class using nfs.csi.k8s.io driver?.........:[y] " yn
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
                read -p "Do you want to use \"nfs-csi\" storage class for \"$i\" volume? (y/n)....................................:[y] " yn
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


# 7> Calcul des tailles des disques persistants

echo -e "7>#################### Size calculation of persistent volumes ###################\n"

# size_calculation () {
copy_to_okd () {
compose=$(docker-compose config --format json)
if [[ $1 = "bind" ]]
	then
		SOURCES=$(echo $compose | jq -r --arg type $1 --arg DIR "${PWD##*/}" '(.services[].volumes[]?|select(.type=="\($type)")|select(.source|test("home|root")))|={source: .source|split("\($DIR)")|.[1], type: .type, target: .target}|del (.services[].volumes[]?|select(.source|test("sock")))| del (.services[].volumes[]?|select(.source|test("/applis")))|.services|to_entries[]|{sources: (.key + ":." + (.value|select(has("volumes")).volumes[]|select(.type=="\($type)")|select(.source!=null)|select(.source|test("(\\.[^.]+)$")|not)|.source))}|.sources')
	else
		SOURCES=$(echo $compose | jq -r --arg type $1 '(.services[].volumes[]?|select(.type=="\($type)")|select(.source|test("home|root")))|={source: .source, type: .type, target: .target}|del (.services[].volumes[]?|select(.source|test("sock")))| del (.services[].volumes[]?|select(.source|test("/applis")))|.services|to_entries[]|{sources: (.key + ":" + (.value|select(has("volumes")).volumes[]|select(.type=="\($type)")|select(.source!=null)|select(.source|test("(\\.[^.]+)$")|not)|.source))}|.sources')
fi
echo $SOURCES
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
        # if [[ ! -d volume_$SVC ]]
        #     then 
        #         mkdir volume_$SVC
        # fi
        # if [[ $(echo $i|grep "/volumes") != '' ]]
        #     then 
        #         sshfs root@diplotaxis4-prod:/opt/pod/item-docker/$SRC volume_$SVC 2> /dev/null
        # else 
        #     sshfs root@diplotaxis4-prod:/$SRC volume_$SVC 2> /dev/null
        # fi
		if [[ $1 = "volume" ]]
			then 
				src="/var/lib/docker/volumes/${NAME}-docker_${SRC_orig}/_data/"
        elif [[  $(echo $SRC |grep "./") != '' ]]
            then
				src="/opt/pod/${NAME}-docker/${SRC}"
		else
			src=$SRC
        fi
        # echo "Calculating needed size for disk claiming......................." 
        # tab1[$index]=$(du -s volume_${SVC} | cut -f1) 
        tab1[$index]=$(ssh root@${diplo} du -s $src | cut -f1) 
		echo $SRC
        echo $SVC:${tab1[$index]}
		if [[ ${tab1[$index]} -lt "100000" ]];
			then
				tab2[$index]="100Mi"
			else
				tab2[$index]=$(echo $(calc "int(${tab1[$index]} / (1024*1024) +1)+1")Gi)
		fi
        echo $SVC:${tab2[$index]}
        tab3[$index]=$(cat $NAME.yml | yq eval -ojson| jq -r --arg size "${tab2[$index]}" --arg svc "$SVC" --arg src "$SRC" '.services |to_entries[] | select(.value.volumes | to_entries[] |.value.source | test("\($src)$"))?|select(.key=="\($svc)")|.value.volumes|=map(select(.source|test("\($src)$"))|with_entries(select(.key="source"))|.source="\($src)"|.size="\($size)")'|jq -s '.[0]|del(..|nulls)')
		
		# $(cat $NAME.yml | yq eval -ojson| 
        #                jq -r --arg size "${tab2[$index]}" --arg svc "$SVC" --arg src "$SRC" '.services
        #                |to_entries[] | select(.value.volumes | to_entries[] |.value.source | 
        #                     test("\($src)"))?|.value.volumes|=
        #                         map(.|=with_entries(select(.key="source"))|.source="\($src)"|.size="\($size)")')
        echo -e "\n"
    done

length=$(echo "${tab3[*]}" | jq -s 'length')
for ((i=0; i<$length; i++ ))
	do
		tab4[$i]=$(echo "${tab3[*]}" | jq -s --arg i "$i" '.[$i|tonumber]')
	done		

# echo "affichage du tableau"
# echo -e "${tab4[*]}"

# exit 1

# Change size of volumeclaim yaml declaration
for i in "${tab4[@]}"; 
    do 
		size=$(echo $i | jq -r '.value.volumes[]?.size'|uniq)
		# echo $size
		source=$(echo $i | jq -r '.value.volumes[]?.source'|uniq)
		# echo $source
        service=$(echo $i | jq -r '.key'|uniq)
		# echo $service
        index=$(echo $i | jq -r --arg size "$size" '.value.volumes[]?.size|index("\($size)")'|uniq)
		# echo $index
		if [[ $1 = "bind" ]]
			then
				file="${service}-claim${index}-persistentvolumeclaim.yaml"
				file_name="${service}-claim${index}"
			else
				file="${source}-persistentvolumeclaim.yaml"
				file_name="${source}"
		fi
		if [[ $i != "null" ]]
			then
				status=$(oc get pvc $file_name -o json | jq -r '.status.phase')
				is_nfs=$(oc get pvc $file_name -o json | jq -r '.spec.storageClassName|test("nfs")')
				while [ $status != "Bound" ]
					do
						status=$(oc get pvc $file_name -o json | jq -r '.status.phase')
					done
				if [[ $is_nfs != "true" ]]
					then
						echo "Resizing $file_name to $size ................"
						cat ${file} | 
							yq eval -ojson| 
							jq --arg size "$size" '.spec.resources.requests.storage=$size'| 
							yq eval -P |
						sponge ${file}
						oc apply -f ${file}
				fi
		fi
    done
# }

read -p "Would you like to copy current data to okd volume of type $1 (may be long)? (y/n).......................................[y]" answer
answer=${answer:-y}
if [[ "$answer" = "y" ]];
    then
		# size_calculation $1
		echo "DEBUG1"
        for i in "${tab4[@]}"; 
            do 
				echo "DEBUG2"
                service=$(echo $i | jq -r '.key')
				echo $service
                # target=$(echo $i | jq -r '.value.volumes[].target')
                target=$(echo $i | jq -r '.value.volumes|last.target')
				echo $target
                # source=$(echo $i | jq -r '.value.volumes[].source')
                source=$(echo $i | jq -r '.value.volumes|last.source')
				echo $source
                private_key=$(cat ~/.ssh/id_rsa)
				echo "DEBUG copy_to_okd)"
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
                echo -e "$service:\n Type those commands to copy data to persistent volume ($size):....................................... \n"
                echo "mkdir /root/.ssh && echo \"$private_key\" > /root/.ssh/id_rsa && chmod 600 -R /root/.ssh; \
if [ \"\$(cat /etc/os-release|grep "alpine")\" = '' ]; \
then apt update && apt install rsync openssh-client -y;  \
else apk update && apk -f add rsync openssh-client-default openssh-client; fi; \
rsync -av -e 'ssh -o StrictHostKeyChecking=no' ${diplo}.v106.abes.fr:${src}/ ${target}/; \
exit"
                echo "###########################################################################"
                POD=$(oc get pods -o json| jq -r --arg service "$service" '.items[]|.metadata|select(.name|test("\($service)-[b-df24-9]+-[b-df-hj-np-tv-z24-9]{5}"))|.name')
                # sleep 10
                oc debug $POD
                # echo "oc rsync --progress=true ./volume_${service} $POD-debug:${target} --strategy=tar"
                # oc rsync --progress=true ./volume_${service} $POD-debug:${target}
            done
fi
}

# 8> Déploiement de l'application

echo -e "8> ######################## Application Deployment #################################\n"
choice=$(
case $1 in
	local) echo -e "oc apply -f \"*.yaml\"\n";;
	*) echo -e "cd $NAME-docker-$1 && \'oc apply -f \"*.yaml\"\'\n";;
esac
)

read -p "Would you like to deploy $NAME on OKD $1?.......................................[y] " answer
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
				while true; do
					read -p "Would you like to create a new project?(y/n)...................................." yn
					case $yn in
						[Yy]* )                         
							echo "Enter the name of the project...................................."
							read project
							oc new-project $project
							echo -e "Setting SCC anyuid to default SA.......................................\n"
							oc adm policy add-scc-to-user anyuid -z default
							echo -e "Creation of docker secret for pulling images without restriction.......................................\n"
							oc create secret docker-registry docker.io --docker-server=docker.io --docker-username=picabesesr --docker-password=SVmx2Puw3scbcb4J
							oc secrets link default docker.io --for=pull
							for i in $(oc get pv -ojson | jq -r '.items[].metadata|select(.name|test("applis-item")).name')
								do
									echo -e "Releasing pv applis-$i..........................................................\n"
									oc patch pv $i -p '{"spec":{"claimRef": null}}'
								done
							echo -e "\n"
							break;;
						[Nn]* )
							echo "Ready to deploy $name. Press \"Enter\" to begin......................................."
							read answer
							oc apply -f "*.yaml*"
							echo -e "\n"
							oc get pods
							echo -e "\n"
							copy_to_okd bind
							copy_to_okd volume
							echo -e "\n";;
						* ) echo "Please answer yes or no.";;
					esac
				done

                # echo "Would you like to create a new project?(y/n)...................................."
                # read answer
                # if [[ "$answer" == "y" ]];
                #     then
                #         echo "Enter the name of the project...................................."
                #         read project
                #         oc new-project $project
                #         echo -e "Setting SCC anyuid to default SA.......................................\n"
                #         oc adm policy add-scc-to-user anyuid -z default
                #         echo -e "Creation of docker secret for pulling images without restriction.......................................\n"
                #         oc create secret docker-registry docker.io --docker-server=docker.io --docker-username=picabesesr --docker-password=SVmx2Puw3scbcb4J
                #         oc secrets link default docker.io --for=pull
				# 		echo "Release pv applis-$NAME-$1..........................................................\n"
				# 		oc patch pv applis-$NAME-$1 -p '{"spec":{"claimRef": null}}'
				# 		echo -e "\n"					
                # fi
                echo "Ready to deploy $name. Press \"Enter\" to begin......................................."
                read answer
                oc apply -f "*.yaml*"
				echo -e "\n"
                oc get pods
				echo -e "\n"
                copy_to_okd bind
				copy_to_okd volume
				echo -e "\n"
        fi
    else
        copy_to_okd bind
		copy_to_okd volume
		# exit 1
fi

# 9> Redémarrage des pods et URL de connexion

echo -e "9>############################ Pods reload #######################\n"
if [[ $answer != "y" ]]; then exit; fi
echo "Restart all $NAME pods......................................." 
oc rollout restart deploy
timeout 10 oc get pods -w
echo -e "Here is the list of configured services: \n"
oc get svc
read -p "Enter a list of above services you want to expose: " services
for i in $services
	do
		oc expose $i
	done
	
# oc expose svc $NAME-front
# URL=$(oc get route -o json | jq --arg NAME "$NAME" -r '.items[]|.spec|select(.host|test("\($NAME)-front"))|.host')
URL=$(oc get route -o json | jq  -r '[.items[]|.spec]|first|.host')
echo -e "Congratulations"
echo -e "You can reach $NAME application at:\n"
echo http://$URL







