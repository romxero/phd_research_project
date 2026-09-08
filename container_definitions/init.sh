#!/bin/bash

set -x

source env/env.sh
#!/bin/bash

logger -s "Building the cuda toolkit"

date

# make the directories
mkdir -p ${CUDA_TOOLKIT_DIR}


# download the runfile
wget -nc -O ./cuda_toolkit-12.9.run \
	https://developer.download.nvidia.com/compute/cuda/12.9.2/local_installers/cuda_12.9.2_575.57.08_linux.run

chmod +x ./cuda_toolkit-12.9.run

./cuda_toolkit-12.9.run --toolkit --toolkit=${CUDA_TOOLKIT_DIR} \
	--installpath=${CUDA_TOOLKIT_DIR} --no-man-page --silent

set +x

exit 0
