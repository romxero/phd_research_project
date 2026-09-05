#!/bin/bash

# Source the environment

source ./env.sh


# Start SurrealDB
./surreal start --log debug --username ${SURREAL_USER} --password ${SURREAL_PASSWORD} --bind ${SURREAL_HOST}:${SURREAL_PORT} \
    --namespace ${SURREAL_NAMESPACE} --database ${SURREAL_DATABASE} > ./surrealdb_
