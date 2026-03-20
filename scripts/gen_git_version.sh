#!/bin/bash 

# This script is used to create unique time based ids for versioning of the project on a git repository. 


MY_HASH=$(openssl rand -hex 4)
MY_TIMESTAMP=$(date +"%m%d%Y%H%M%S")

# version format: YYYYMMDDHHMMSS_HASH
MY_VERSION="$MY_TIMESTAMP_$MY_HASH"

echo "Version: $MY_VERSION"


read -p "Are you sure you want to create and push the version $MY_VERSION? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "Version $MY_VERSION not created and pushed to origin"
    exit 1
fi


git tag -a $MY_VERSION -m "Version $MY_VERSION"

git push origin $MY_VERSION

echo "Version $MY_VERSION created and pushed to origin"

