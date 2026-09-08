#!/bin/bash 

# This is used to set the environment variables for the project
MY_ENV_ARRAY=(
  "GIT_PAGER=cat"
  "INF_ENGINE=vllm"
  "MODEL=llama"
)

# Location of the root project directories
MAIN_ENV_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
MAIN_SCRIPT_DIR=$(echo $MAIN_ENV_DIR | perl -pe 's/\/env//g')

# Project name
PROJ_NAME="phd_research_project"

# Application name
APP_NAME="RAD-MTA"

LOG_DIR="../logs"



# Every variable in the array is exported into the user environment
for env_var in "${MY_ENV_ARRAY[@]}"; do
  
  export "${env_var}"

done

# end 
