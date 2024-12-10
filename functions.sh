#!/bin/bash

### functions used by compose2manifests.sh 

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
	echo -e "A video usecase is available at: https://vimeo.com/1022133270/90cfd9e0a7\n" 
	exit 1
}

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

#Calcul des tailles des disques persistants
copy_to_okd () {
	echo $2
if [[ $1 = "bind" ]]
	then
		SOURCES=$(cat $2 | yq -ojson | jq -r --arg type $1 --arg DIR "${PWD##*/}" '(.services[].volumes[]?|select(.type=="\($type)")|select(.source|test("home|root")))|={source: .source|split("\($DIR)")|.[1], type: .type, target: .target}|del (.services[].volumes[]?|select(.source|test("sock")))| del (.services[].volumes[]?|select(.source|test("/applis")))|.services|to_entries[]|{sources: (.key + ":." + (.value|select(has("volumes")).volumes[]|select(.type=="\($type)")|select(.source!=null)|select(.source|test("(\\.[^.]+)$")|not)|.source))}|.sources')
	else
		SOURCES=$(cat $2 | yq -ojson | jq -r --arg type $1 '(.services[].volumes[]?|select(.type=="\($type)")|select(.source|test("home|root")))|={source: .source, type: .type, target: .target}|del (.services[].volumes[]?|select(.source|test("sock")))| del (.services[].volumes[]?|select(.source|test("/applis")))|.services|to_entries[]|{sources: (.key + ":" + (.value|select(has("volumes")).volumes[]|select(.type=="\($type)")|select(.source!=null)|select(.source|test("(\\.[^.]+)$")|not)|.source))}|.sources')
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
				if [ -n "$docker_host" ]; 
					then
						tab1[$index]=$(ssh root@${docker_host} du -s $src | cut -f1 ) 
					else
						tab1[$index]=''
				fi
				echo "$SRC"
				echo "$SVC:$(blue ${tab1[$index]})"
				if [[ ${tab1[$index]} -lt "100000" ]];
					then
						tab2[$index]="100Mi"
					else
						tab2[$index]=$(echo $(calc "int(${tab1[$index]} / (1024*1024) +1)+1")Gi)
				fi

				echo "$SVC:$(blue ${tab2[$index]})"
				tab3[$index]=$(cat $2 | yq eval -ojson| jq -r --arg size "${tab2[$index]}" --arg svc "$SVC" --arg src "$SRC" '.services |to_entries[] | select(.value.volumes | to_entries[] |.value.source | test("\($src)$"))?|select(.key=="\($svc)")|.value.volumes|=map(select(.source|test("\($src)$"))|with_entries(select(.key="source"))|.source="\($src)"|.size="\($size)")'|jq -s '.[0]|del(..|nulls)')
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
		if [ "VARS_TYPE" != "copy" ];then
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
		fi	

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
if [ \"\$(cat /etc/os-release|grep "debian")\" != '' ]; \
then apt update && apt install rsync openssh-client -y;  \
elif [ \"\$(cat /etc/os-release|grep rhel)\" != '' ]; \
then yum -y install openssh-clients rsync; \
else apk update && apk -f add rsync openssh-client-default openssh-client; fi; \
rsync -a --info=progress2 -e 'ssh -o StrictHostKeyChecking=no' ${docker_host}:${src}/ ${target}/; \
exit"
							echo "###########################################################################"
							# while [ "$pod_status" != "Running" ] && [ -n "$file_name" ]
							while [ "$pod_status" != "Running" ]
								do
									if [ "$PROVIDER" = "kubernetes" ] || [ "$PROVIDER" = "" ]
										then 
											POD=$(oc get pods -o json| jq -r --arg service "$service" '.items[]|.metadata|select(.name|test("\($service)-[b-df24-9]+-[b-df-hj-np-tv-z24-9]{5}"))|.name')
										else
											POD=$(oc get pods -o json| jq -r --arg service "$service" '.items[]|.metadata|select(.name|test("\($service)-[1-9]+-[b-df-hj-np-tv-z24-9]{5}"))|.name')
									fi
									echo "Waiting for $(blue \"$service\") pod to be in running state...."
									pod_status=$(oc get pod $POD -o json | jq -r '.status.phase')
									sleep 1
								done
							echo "oc debug $POD --as-root=true"
							oc debug $POD --as-root=true
							pod_status=""
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