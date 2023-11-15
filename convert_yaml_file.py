import yaml
import json
import argparse
from rich.console import Console

console = Console()
list_elem2retreive=[]
list_keys2retreive=[]
nicelist_keys2retreive={}

parser = argparse.ArgumentParser(description='Conversion fichier yaml.')

parser.add_argument('-f', help='nom du fichier yml en entrée.', required=True,type=str)
parser.add_argument('-out', help='nom du fichier yml en sortie.', required=True,type=str)
parser.add_argument('-dir', help='nom du repertoire en sortie pour les fichiers txt extraits.', required=True,type=str)

arguments = parser.parse_args()

if arguments.f:
    console.print("Vous avez choisi de convertir le fichier yml : " + str(arguments.f), style="bold green")
if arguments.out:
    console.print("Dans le fichier yml de sortie : " + str(arguments.out), style="bold blue")
if arguments.dir:
    console.print("Les fichiers txt ainsi que le fichier convertit seront extraits/convertit dans : " + str(arguments.dir), style="bold blue")

# Chemin vers le fichier YAML
chemin_fichier = arguments.f

secrets_str="secrets:\n"
secrets_str = secrets_str+"  mdp:\n"
secrets_str = secrets_str+"    file:mdp.txt\n"

# Ouverture du fichier YAML et chargement de son contenu dans une variable
with open(chemin_fichier, 'r') as fichier:
    contenu = yaml.safe_load(fichier)

safe_copy = contenu
file=open("./input/source.json","w")
json.dump(safe_copy,file)
file.close()
safe_copy["secrets"] = dict()
safe_copy["secrets"]['mdp'] = dict()
safe_copy['secrets']['mdp']['file']='mdp.txt'

for key, value in contenu['services'].items():
    #nicelist_keys2retreive[key] = dict()
    if isinstance(value, dict):
        for sub_key, sub_value in value.items():
           if isinstance(sub_value, dict):
               for subsub_key, subsub_value in sub_value.items():
                   #console.print(key+" / "+str(sub_key)+" / "+str(sub_value)+" / "+str(subsub_key)+" / "+str(subsub_value), style="bold green")
                   if "KEY" in subsub_key or "PASSWORD" in subsub_key:
                       #console.print(key + " / " + str(sub_key) + " / " + str(sub_value) + " / " + str(subsub_key) + " / " + str(subsub_value), style="bold green")
                       if subsub_key not in list_elem2retreive:
                           list_elem2retreive.append(subsub_key)
                           list_keys2retreive.append(key+"/"+sub_key+"/"+subsub_key)
                           secrets_str = secrets_str + "  "+subsub_key+":\n"
                           secrets_str = secrets_str + "    file: " + subsub_key + ".txt\n"
                           safe_copy['secrets'][subsub_key]=dict()
                           safe_copy['secrets'][subsub_key]['file']=subsub_key+'.txt'

           else:
               #console.print(key+" / "+str(sub_key)+" / "+str(sub_value), style="bold green")
               if "KEY" in sub_key or "PASSWORD" in sub_key:
                   if sub_key not in list_elem2retreive:
                       list_elem2retreive.append(sub_key)
                       list_keys2retreive.append(key + "/" + sub_key)
                       secrets_str = secrets_str + "  " + sub_key + ":\n"
                       secrets_str = secrets_str + "    file: " + sub_key + ".txt\n"
                       safe_copy['secrets'][sub_key] = dict()
                       safe_copy['secrets'][sub_key]['file'] = sub_key + '.txt'

    else:
       #console.print(key+" / "+value, style="bold green")
       if "KEY" in key or "PASSWORD" in key:
           if key not in list_elem2retreive:
               list_elem2retreive.append(key)
               secrets_str = secrets_str + "  " + key + ":\n"
               secrets_str = secrets_str + "    file: " + key + ".txt\n"
               safe_copy['secrets'][key] = dict()
               safe_copy['secrets'][key]['file'] = key + '.txt'

console.print("Liste des cles sur SERVICES yaml contenant KEY ou PASSWORD : " + str(nicelist_keys2retreive),
                         style="bold red")

console.print("Liste des cles yaml contenant KEY ou PASSWORD : "+str(list_elem2retreive), style="bold blue")
console.print("Liste des cles COMPLETES yaml contenant KEY ou PASSWORD : "+str(list_keys2retreive), style="bold blue")
console.print("Contenu de la var THESES_KIBANA_PASSWORD : "+str(contenu['services']['theses-elasticsearch-setupusers']['environment']['THESES_KIBANA_PASSWORD']), style="bold blue")

i = 1
list_secrets = []
for value in list_keys2retreive:
    elements = value.split("/")
    #console.print("value KEY to create in secrets section on "+elements[0]+" : " + str(elements), style="bold green")
    #console.print(contenu['services'][elements[0]][elements[1]][elements[2]] + " à effacer.", style="bold magenta")
    f = open(arguments.dir+elements[2]+".txt", "w")
    f.write(contenu['services'][elements[0]][elements[1]][elements[2]])
    f.close()
    if 'environment' in safe_copy['services'][elements[0]]:
        del safe_copy['services'][elements[0]]['environment'][elements[2]]

    if 'secrets' not in safe_copy['services'][elements[0]]:
        console.print("CREATION pour "+elements[0]+" de contenu['services']["+elements[0]+"]['secrets'] ", style="bold magenta")
        safe_copy['services'][elements[0]]['secrets'] = ""
        list_secrets.append(elements[2])
        i = i + 1
        safe_copy['services'][elements[0]]['secrets'] = list_secrets
        console.print("liste secrets générée : \n" + str(list_secrets) + " POUR "+str(safe_copy['services'][elements[0]]['secrets'])+" COMPTEUR =>"+str(i)+"<=", style="bold red")

    #console.print("CREATION de contenu["+str(elements)+"]['secrets'] "+str(elements[2])+" // "+str(safe_copy['services'][elements[0]]['secrets']), style="bold magenta")
    #for elem in elements:
    #    console.print("value : " + str(elem), style="bold magenta")

console.print("secrets générés : \n" + secrets_str, style="bold red")
#safe_copy['secrets']=secrets_str

file=open(arguments.dir+arguments.out,"w")
yaml.dump(safe_copy, file)
file.close()