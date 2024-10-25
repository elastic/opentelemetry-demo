#!/bin/bash

SCRIPTS_DIR=$(dirname "${BASH_SOURCE[0]}")
LOAD_ENV_FILE_PATH=$SCRIPTS_DIR/.env

set -a
source $SCRIPTS_DIR/shared.sh
set +a

if [ -n "${ENV_FILE_PATH}" ]; then
  LOAD_ENV_FILE_PATH=$ENV_FILE_PATH
fi

if [ -f $LOAD_ENV_FILE_PATH ]; then
  title "Sourcing environment variables from $LOAD_ENV_FILE_PATH"
  source $LOAD_ENV_FILE_PATH
else
  warn "Environment variables file not found at $LOAD_ENV_FILE_PATH"
fi