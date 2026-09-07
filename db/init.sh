#!/bin/bash

# Source the environment

source env/env.sh

MY_OPTIONS=$@


if [[$@ -eq 0]]
then 

	echo "you need to supply options to this command\n" 

fi




# Start SurrealDB
./surreal start --log debug --username ${SURREAL_USER} --password ${SURREAL_PASSWORD} --bind ${SURREAL_HOST}:${SURREAL_PORT} \
    --namespace ${SURREAL_NAMESPACE} --database ${SURREAL_DATABASE} > ${LOG_DIR}/surrealdb_init.log 2>&1 & disown
