#!/binbash

patch_expose () {
    services=$(docker-compose config | yq -o json| jq -r '.services|to_entries[]|.value|select((has("ports") or has("expose"))|not)?|."container_name"')
    if [[ -n $services ]]
        then
            echo -e "The following services don't have any explicit defined ports: \n$services"
            echo "You may define them one by one so as the conversion to be successfull"
            for service in $services; 
                do 
                    read -p "$service: Enter port number to expose the service in json format (ex: [80,8088], press to leave empty): " port
                    port=${port:-[]}
                    if [[ -n $service ]]
                        then
                            if [[ $port != '[]' ]]
                                then
                                    docker-compose config | yq -o json | jq --arg service "$service" --argjson port "$port" '.services."\($service)".expose+=$port' \
                                    |sponge docker-compose.yml
                            fi
                    fi
                done
            cat docker-compose.yml | yq -P | sponge docker-compose.yml
        fi
}

patch_expose_auto () {
    services=$(docker-compose -f $CLEANED config | yq -o json| jq -r '.services|to_entries[]|.value|select((has("ports") or has("expose"))|not)?|."container_name"')
    if [[ -n $services ]]
        then
			for service in $services; 
				do 
					port=$(ssh root@$diplo docker inspect $service | jq -cr '[.[].NetworkSettings.Ports|to_entries[]|.key|split("/")|.[0]'])
                    port=${port:-[]}
                    if [[ $port != '[]' ]]
                        then
                            echo "Patching ports $port for service $service ............"
                            docker-compose -f $CLEANED config | yq -o json | jq --arg service "$service" --argjson port "$port" '.services."\($service)".expose+=$port' \
                            |sponge $CLEANED
                    fi
				done
			cat $CLEANED | yq -P | sponge $CLEANED
	fi
}

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

patch_configmaps () {
for i in $(cat movies.yml | yq -ojson| jq -r '.services|keys[]')
    do 
        echo "####$i####"
        sources=$( cat movies.yml | yq -ojson| jq -r  --arg i $i '.services|to_entries[]|select(.key=="\($i)").value.volumes[]?|select(.source|test("(\\.[^.]+)$")).source|split("/")|last' )
        echo "sources: $sources"
        for j in $sources
            do
                echo -e "patching ${i}-deployment.yaml with source $j......."
                filename=$(cat $i-deployment.yaml | yq -ojson | jq -r --arg j "$j" '.spec.template.spec.containers[].volumeMounts[]?|select(.mountPath|test("\($j)"))|((.name|split("-claim")|.[0] )  + "-" + (.mountPath|split("/")|last|gsub("_";"-")|gsub("\\.";"-")|ascii_downcase))')
                echo -e "fichier: $filename \n"
                cat ${i}-deployment.yaml | yq -ojson | \
                jq -r --arg filename $filename --arg j $j '((.spec.template.spec.containers[].volumeMounts[]?|select((.mountPath|test("(\\.[^.]+)$")) and (.name|test("claim")) )) |= {mountPath: .mountPath, name: $filename, subPath: $j })|.spec.template.spec.volumes+=[{configMap: {defaultMode: 420, name: $filename}, name: $filename}]' | yq -P | \
                sponge ${i}-deployment.yaml 
            done
    done
}

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
        echo "yaya $i"
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
        echo "Calculating needed size for disk claiming......................." 
        # tab1[$index]=$(du -s volume_${SVC} | cut -f1) 
        echo $src
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
				echo "DEBUG copy_to_okd"
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

create_pv() {
for i in $(echo $nfs_services|jq -r '.key'); do \
source=$(echo $nfs_services|jq --arg i "$i" -r 'select(.key==$i)|.value.volumes[0].source|split("/")|.[1]')
echo $source
cat <<EOF > $i-pv-nfs-$source-persistentvolume.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $source-$i-qualimarc
spec:
  capacity:
    storage: 8Ti
  accessModes:
  - ReadWriteMany
  nfs:
    path: $(echo $nfs_mount_point |jq -r --arg source "$source" 'select("\(.mount_point)"|test("\($source)")).path')
    server: $(echo $nfs_mount_point |jq -r --arg source "$source" 'select("\(.mount_point)"|test("\($source)")).server')
  persistentVolumeReclaimPolicy: Retain
EOF
done
}

create_pv2() {
# diplo=$(for i in {1..6}; \
# do ssh root@diplotaxis$i-${1}.v106.abes.fr docker ps --format json | jq --arg toto "diplotaxis${i}-${1}" '{diplotaxis: ($toto), nom: .Names}'; \
# done \
# | jq -rs --arg var "$2" '[.[] | select(.nom | test("^\($var)-.*"))]|first|.diplotaxis'); \
diplo=diplotaxis1-test
echo -e "$2 is running on $diplo\n"

nfs_mount_point=$(ssh root@$diplo mount | \
					jc --mount | \
					jq -r '.[]|select(.type|test("nfs"))
					|{
					  path: .filesystem|split(":")|last, 
					  rep: .filesystem|split("/")|last|gsub("_";"-")|gsub("\\.";"-"),
					  mount_point: .mount_point, 
					  server: .filesystem|split(":")|first
					 }' \
				 )

for i in $(echo $nfs_mount_point|jq -r '."mount_point"|split("/")|last')
    do 
		nfs_service=$(cat $2.yml | \
					  yq -ojson | \
					  jq -r --arg i "$i" '.services|to_entries[]|select(.value|has("volumes"))|select(.value.volumes[]|select(.source|test("\($i)")))?' )
		if [[ -n $nfs_service ]]
			then 
				nfs_services=$nfs_service
		fi
		# echo $nfs_services|jq
		# echo $i
    done

echo $nfs_services|jq
# Get project for pvc naming
project=$(oc config view --minify -o 'jsonpath={..namespace}')
# index="-1"

for i in $(echo $nfs_services|jq -r '.key'); do \
# index=$((index +1))
# echo "index: $index"
echo $i
vol_nb=$(cat theses.yml|yq -ojson |jq --arg i "$i" --arg pwd "${PWD##*/}" -r '.services|to_entries[]
		|select(.key=="theses-api-export")
		|.value.volumes|length')
# echo $vol_nb

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

subpath=$(echo $nfs_services \
		|jq --arg i "$i" --arg pwd "${PWD##*/}" --arg source "$source" -r \
		'select(.key==$i)|(
							if (.value.volumes[0].source|split("\($pwd)/")|.[1] != null) 
							then .value.volumes[0].source|split("\($pwd)")|.[1]|split("\($source)")|last
							else .value.volumes[0].source|split("\($source)")|last
							end
						  )' \
		)

source_renamed=$(echo $source | sed 's/_/-/g' | sed 's/\./-/g' | tr '[:upper:]' '[:lower:]')
echo "Creating $i-pv$index-nfs-$source_renamed-persistentvolume.yaml ........................................."
cat <<EOF > $i-pv$index-nfs-$source_renamed-persistentvolume.yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $i-pv${index}-nfs-$source_renamed-$1
spec:
  capacity:
    storage: 8Ti
  accessModes:
  - ReadWriteMany
  nfs:
    path: $(echo $nfs_mount_point |jq -r --arg source "$source" 'select("\(.mount_point)"|test("\($source)$")).path')
    server: $(echo $nfs_mount_point |jq -r --arg source "$source" 'select("\(.mount_point)"|test("\($source)$")).server')
  persistentVolumeReclaimPolicy: Retain
EOF

create_pvc_nfs $1
patch_deploy_nfs $1
done 
done   

}

create_pvc_nfs() {
	# index="-1"
	# for i in $applis_svc; 
	# 	do  
			# index=$(cat $2.yml | yq eval -ojson | jq -r  --arg applis_svc "$3" --arg source "$source" '.services|to_entries[]| [{services: .key, volumes: .value.volumes[]|select(.source|test("\($source)"))}]?|to_entries[]|select(.value.services=="\($applis_svc)").key')
			# echo $index
			# for j in $(echo $index);
			# 	do
					echo "patching $source_renamed in $i-claim$index-nfs-persistentvolumeclaim.yaml ......................................."
					cat $i-claim$index-persistentvolumeclaim.yaml | 
						yq eval -ojson | 
							jq --arg project "$project" --arg name "$i" --arg env "$1" --arg source_renamed "$source_renamed" --arg index "$index" \
							'.metadata.name|="\($name)-claim\($index)-nfs-\($source_renamed)-\($env)"
							|.metadata.labels."io.kompose.service"|="\($name)-claim\($index)-nfs-\($source_renamed)-\($env)"
							|.spec.resources.requests.storage="8Ti"
							|.spec.volumeName="\($name)-pv\($index)-nfs-\($source_renamed)-\($env)"
							|.spec.storageClassName=""|.spec.accessModes=["ReadWriteMany"]' |
						yq eval -P | sponge $i-claim$index-persistentvolumeclaim.yaml
				# done
		# done
}

patch_deploy_nfs() {

	oldname=$i-claim0
	echo $oldname
	newname="$i-pv${index}-nfs-${source_renamed}-$1"
	echo $newname     
	cat $i-deployment.yaml | yq -ojson | \
							jq --arg newname "$newname" --arg oldname "$oldname" --arg subpath "$subpath" \
							'(.spec.template.spec.containers[0].volumeMounts[]|select(.name=="\($oldname)"))+= ({subpath:"\($subpath)"}|.name|="\($newname)")|
							 (.spec.template.spec.volumes[]|select(.name=="\($oldname)"))|=(.name|="\($newname)"|.persistentVolumeClaim.claimName|="\($newname)")' | yq -P | sponge $i-deployment.yaml
}

# patch_expose_auto
# patch_secretKeys
# patch_configmaps
# copy_to_okd $1
create_pv2 $1 $2