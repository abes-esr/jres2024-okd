NAME=movies
SOURCES=$(for i in $(cat $NAME.yml | yq eval -ojson| 
                                    jq -r '.services|to_entries[] |
                                                     select(.value.volumes|
                                                     to_entries[]|
                                                     .value.source|
                                                     test("applis")|not)?|
                                                     .value.volumes|map(.source)[]'); 
                do 
                    SERVICE=$(cat $NAME.yml | yq eval -ojson| 
                                            jq -r --arg service "$i" '.services|to_entries[] |
                                                                select(.value.volumes | 
                                                                to_entries[] |
                                                                .value.source | 
                                                                test("\($service)"))? |
                                                                .key')
                    REP=$(pwd); 
                    if [[ $(echo "$i"|grep $REP) != '' ]];
                    then
                        echo $SERVICE:$(echo $i | awk -F"$REP" '{print $2}'); 
                    else 
                        echo $SERVICE:$i; 
                    fi; 
                done)
echo $SOURCES

cat movies.yml | yq eval -ojson| jq --arg DIR "${PWD##*/}" -r '.services|to_entries[]?|{service: .key, volume: .value.volumes[]?|select(.source|test("/appli")|not)|select(.type=="bind")}|.volume.source|=split("\($DIR)")|.[1]'
cat movies.yml | yq eval -ojson| jq --arg DIR "${PWD##*/}" '(.services[].volumes[]?|select(.type=="bind"))|={source: .source|split("\($DIR)")|.[1]}'
cat movies.yml | yq eval -ojson| jq --arg DIR "${PWD##*/}" '.services|to_entries[]|.value|select(has("volumes")).volumes|to_entries[]|.value|select(.type=="bind")'
# display services with type bind
cat movies.yml | yq eval -ojson| jq --arg DIR "${PWD##*/}" '(.services[].volumes[]?|select(.type=="bind"))|={source: .source|split("\($DIR)")|.[1], type: .type}|.services|to_entries[]|{service: .key, volume: .value|select(has("volumes")).volumes[]|select(.type=="bind")|select(.source!=null)}' | jq -s | yq eval -P
# display a build service:source with "bind" and "applis" filter
cat movies.yml | yq eval -ojson| jq -r --arg DIR "${PWD##*/}" '(.services[].volumes[]?|select(.type=="bind")|select(.source!="/applis"))|={source: .source|split("\($DIR)")|.[1], type: .type, target: .target}|.services|to_entries[]|{services: (.key + ":" + (.value|select(has("volumes")).volumes[]|select(.type=="bind")|select(.source!=null)|.source))}|.services'