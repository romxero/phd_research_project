#!/bin/bash


# This script preprocesses the records in the jsonl files for ingestion in the database. 


_JSONL_FILE=$1



rsync ${PWD}/${_JSON_FILE} ${PWD}/${_JSON_FILE}.bak

perl -pi.bak -e 's/\"id\":/\"reddit_id\":/g' ${PWD}/${_JSON_FILE}


exit 0 


#Only the top-level key. Nested "id" exists under preview.images, awards, gallery items, and crosspost_parent_list. A global s/"id":/"reddit_id":/g will corrupt those. Use a JSON-aware rewrite (jq 'if has("id") then .reddit_id = .id | del(.id) else . end'), not a regex.

