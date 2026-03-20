#!/bin/bash 
# this script inspects the jsonl object and uses gron to parse the json easily with grep 
#set -x 
#GREP_PATTERN="xargs"

if ! command -v gron &> /dev/null; then
  echo "gron is not found in PATH."
  # Perform actions if the command is missing
fi
if ! [[ $1 ]]; then 
    echo "Usage: $0 <file>"
    exit 1
fi

# main loop
while read -r line; do
  if [[ ${2} ]]; then
    echo ${line} | gron | grep ${2} # grep pattern to use for the json line object
  else
    echo ${line} | gron 
  fi
    sleep 1
done < ${1}


exit 0 



#cat r_natalism_posts.jsonl | gron
