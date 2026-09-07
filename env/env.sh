#!/bin/bash 

# This is used to set the environment variables for the project
MY_ENV_ARRAY=(
  "GIT_PAGER=cat"
  "INF_ENGINE=vllm"
  "MODEL=llama"
)


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