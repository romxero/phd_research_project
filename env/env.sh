#!/bin/bash 

# this is an environment file that helps with selecting the apropriate model and inference engine

# Location of the root project directories
MAIN_ENV_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
MAIN_SCRIPT_DIR=$(echo $MAIN_ENV_DIR | perl -pe 's/\/env//g')


ENV_ARRAY=(

"GIT_PAGER=cat"

)


for vars in ${ENV_ARRAY[@]};
do
	export "${vars}"

done

source ${MAIN_SCRIPT_DIR}/db/env/env.sh


PROJ_DIRECTORIES=(

container_definitions
db
downloads
env
logs
os_env
scripts
.proj_state

)

for proj_dirs in ${PROJ_DIRECTORIES[@]};
do

	mkdir -p ${proj_dirs} 
done


