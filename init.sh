#!/bin/bash

# this currently assumes linux os is installed.

# env

export UV_VENV_CLEAR=1

# create the home directory that will download uv and everything

if command -v wget &> /dev/null ; then
    echo "wget is installed"
else
    echo "wget is not installed"
    echo "Please install wget"
    exit 1
fi


# set up the environment
pushd ${HOME}

mkdir -p my_bin/bin my_bin/lib my_bin/etc my_bin/share my_bin/include

if [[ -f ${HOME}/.my_env ]]; then
    unlink ${HOME}/.my_env

fi


touch ${HOME}/.my_env

echo "export PATH=${HOME}/my_bin/bin:\$PATH" >> ${HOME}/.my_env
echo "export LD_LIBRARY_PATH=${HOME}/my_bin/lib:\$LD_LIBRARY_PATH" >> ${HOME}/.my_env
echo "export C_INCLUDE_PATH=${HOME}/my_bin/include:\$C_INCLUDE_PATH" >> ${HOME}/.my_env
echo "export CPLUS_INCLUDE_PATH=${HOME}/my_bin/include:\$CPLUS_INCLUDE_PATH" >> ${HOME}/.my_env
echo "export LIBRARY_PATH=${HOME}/my_bin/lib:\$LIBRARY_PATH" >> ${HOME}/.my_env
echo "export PKG_CONFIG_PATH=${HOME}/my_bin/lib/pkgconfig:\$PKG_CONFIG_PATH" >> ${HOME}/.my_env
echo "export MANPATH=${HOME}/my_bin/share/man:\$MANPATH" >> ${HOME}/.my_env
echo "export INFOPATH=${HOME}/my_bin/share/info:\$INFOPATH" >> ${HOME}/.my_env



grep -q "source \${HOME}/.my_env" ${HOME}/.bashrc || echo "source \${HOME}/.my_env" >> ${HOME}/.bashrc



# make sure we have uv

if  command -v uv &> /dev/null ; then
    echo "uv is installed"
else
    echo "installing uv"

    wget https://github.com/astral-sh/uv/releases/download/0.9.15/uv-x86_64-unknown-linux-gnu.tar.gz -O ./uv.tar.gz
    if [ "$?" -ne 0 ]; then
        echo "Failed to download uv"
        exit 1
    fi

    tar -xzf ./uv.tar.gz -C /tmp/
    if [ "$?" -ne 0 ]; then
        echo "Failed to extract uv"
        exit 1
    fi

    mv /tmp/uv-x86_64-unknown-linux-gnu/* ${HOME}/my_bin/bin/

    if [ "$?" -ne 0 ]; then
        echo "Failed to move uv"
        exit 1
    fi

    rm ./uv.tar.gz
fi

popd


source ${HOME}/.bashrc


bash -l -c "$HOME/my_bin/bin/uv venv"

bash -l -c "source .venv/bin/activate; $HOME/my_bin/bin/uv pip install -r ./requirements.txt"


exit 0
