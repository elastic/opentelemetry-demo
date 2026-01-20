#!/usr/bin/env bash
set -euo pipefail
# Place your common test setup here

# Source environment files to match Makefile behavior
set -a
# Check if .env files exist in repo root or current directory
# if [ -f "../.env" ]; then
#     source "../.env"
# elif [ -f ".env" ]; then
#     source ".env"
# fi
if [ -f "../.env.override" ]; then
    source "../.env.override"
elif [ -f ".env.override" ]; then
    source ".env.override"
fi
set +a

CURRENT_DIR=$(pwd)
export CURRENT_DIR
export START_LOCAL_DIR="${CURRENT_DIR}/elastic-start-local"
export START_LOCAL_ENV_PATH="${START_LOCAL_DIR}/.env"
export START_LOCAL_UNINSTALL_FILE="${START_LOCAL_DIR}/uninstall.sh"

