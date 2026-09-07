#!/bin/bash

# Source the environment
source env/env.sh

APP_NAME=RAD-MTA

if ! command -v ollama >/dev/null 2>&1; then
  echo -e "Ollama not installed. Stage it \n" 
  exit 1

fi 

if pgrep -f "ollama serve" >/dev/null 2>&1; then
  echo -e "Ollama is already running. Kill it first.\n"
  exit 1
fi

# Start Ollama
ollama serve > ../logs/ollama_serve.log 2>&1 & disown

exit 0 