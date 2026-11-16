#!/bin/bash

set -x  # print the commands as they are executed
set -e  # exit the script if any command fails

INF_PORT_NUM=${1:-65003}
INF_HOSTNAME=${2:-localhost}

echo "Running text-embeddings-inference on port ${INF_PORT_NUM}"

apptainer exec --nv --bind ~/hf_hub/hub:/data ./text-embeddings-inference_120-1.9.sif bash -c "HF_HUB_OFFLINE=1 text-embeddings-router \
  --model-id Alibaba-NLP/gte-modernbert-base \
  --dtype float16 \
  --port ${INF_PORT_NUM} \
  --hostname ${INF_HOSTNAME} \
  --max-batch-tokens 8192 \
  --auto-truncate false \
  --payload-limit 8000000
"

exit 0 

