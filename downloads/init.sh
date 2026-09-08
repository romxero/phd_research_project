#!/bin/bash 


source env/env.sh 


logger -s "Downloading the required files for this project...." 


# Rclone
logger -s "Grabbing RCLONE" 

wget -nc -O rclone.zip https://downloads.rclone.org/v1.75.1/rclone-v1.75.1-linux-amd64.zip

if [[ $? -ne 0 ]] 
then 

	logger -s "error getting rclone"
	exit 1

fi



# download the runfile
logger -s "Grabbing Cuda Toolkit Version 12.9"

wget -nc -O ./cuda_toolkit-12.9.run \
        https://developer.download.nvidia.com/compute/cuda/12.9.2/local_installers/cuda_12.9.2_575.57.08_linux.run


if [[ $? -ne 0 ]]
then

        logger -s "error getting cuda toolkit 12.9"
        exit 1

fi
