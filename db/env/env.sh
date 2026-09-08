#!/bin/bash

# This is the main environment for the dbms directory, and application; surrealdb

# Location of the Database scripts
DB_ENV_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
DB_SCRIPT_DIR=$(echo $DB_ENV_DIR | perl -pe 's/\/env//g')

# SurrealDB password
SURREAL_PASSWORD="83e107dafc41b716e859b10d2bd94f4e"

# SurrealDB host
SURREAL_HOST="0.0.0.0"

# SurrealDB port
SURREAL_PORT="65005"

# DBMS table/namespace/db prefix

DBMS_STRING_PREFIX="phd_research_pronatalism"

# SurrealDB namespace
SURREAL_NAMESPACE="${DBMS_STRING_PREFIX}_namespace"

# SurrealDB database
SURREAL_DATABASE="${DBMS_STRING_PREFIX}_db"

# surreal user
SURREAL_USER="root"

