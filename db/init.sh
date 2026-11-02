#!/bin/bash


source env/env.sh

./surreal start --log debug --username ${SURREAL_USER} --password ${SURREAL_PASSWORD} --bind ${SURREAL_HOST}:${SURREAL_PORT} \
    --namespace ${SURREAL_NAMESPACE} --database ${SURREAL_DATABASE} > ${SURREAL_LOG_FILE_NAME} 2>&1 & disown


TMP_SQL_FILE=$(mktemp /tmp/${DBMS_STRING_PREFIX}_import.sql.XXXXXX)

cat <<EOF > ${TMP_SQL_FILE}

-- make sure to use the import clause
OPTION IMPORT;

-- define the database
DEFINE NAMESPACE ${SURREAL_NAMESPACE};

-- use the namespace
USE NS ${SURREAL_NAMESPACE};

-- define the database
DEFINE DATABASE ${SURREAL_DATABASE};

EOF

cat ${TMP_SQL_FILE} | ./surreal sql -u ${SURREAL_USER} -p ${SURREAL_PASSWORD} -e ws://${SURREAL_HOST}:${SURREAL_PORT}
if [ $? -ne 0 ]; then
    echo "Failed to import data into SurrealDB"
    exit 1
fi


unlink ${TMP_SQL_FILE}

exit 0
