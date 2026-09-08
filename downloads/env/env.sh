#!/bin/bash

# Location of the downloads directory

DOWNLOADS_ENV_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)
DOWNLOADS_SCRIPT_DIR=$(echo $MAIN_ENV_DIR | perl -pe 's/\/env//g')



