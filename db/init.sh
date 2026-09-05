#!/bin/bash

# SurrealDB password
SURREAL_PASSWORD="83e107dafc41b716e859b10d2bd94f4e"

# SurrealDB host
SURREAL_HOST="0.0.0.0"

# SurrealDB port
SURREAL_PORT="65005"

# SurrealDB namespace
SURREAL_NAMESPACE="phd_research_namespace"

# SurrealDB database
SURREAL_DATABASE="phd_research_db"

# surreal user  
SURREAL_USER="root"

# Start SurrealDB
./surreal start --log debug --username ${SURREAL_USER} --password ${SURREAL_PASSWORD} --bind ${SURREAL_HOST}:${SURREAL_PORT} \
    --namespace ${SURREAL_NAMESPACE} --database ${SURREAL_DATABASE}

