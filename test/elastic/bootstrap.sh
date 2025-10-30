#!/usr/bin/env bash
set -euo pipefail
# Place your common test setup here

CURRENT_DIR=$(pwd)
START_LOCAL_DIR="${CURRENT_DIR}/elastic-start-local"
START_LOCAL_ENV_PATH="${START_LOCAL_DIR}/.env"
START_LOCAL_UNINSTALL_FILE="${START_LOCAL_DIR}/uninstall.sh"