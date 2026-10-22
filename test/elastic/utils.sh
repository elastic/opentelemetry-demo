#!/usr/bin/env bash

set -e -o pipefail

# Returns the HTTP status code from a call
# usage: get_http_response_code url username password
function get_http_response_code() {
  url=$1
  if [ -z "$url" ]; then
    echo "Error: you need to specify the URL for get the HTTP response"
    exit 1
  fi
  username=$2
  password=$3

  if [ -z "$username" ] || [ -z "$password" ]; then
    result=$(curl -LI "$url" -o /dev/null -w '%{http_code}\n' -s)
  else
    result=$(curl -LI -u "$username":"$password" "$url" -o /dev/null -w '%{http_code}\n' -s)
  fi

  echo "$result"
}

function start_local_elastic_stack() {
  curl -fsSL https://elastic.co/start-local | sh -s -- --esonly --edot >/dev/null
  set -a
  source "${START_LOCAL_ENV_PATH}"
  set +a
  result=$(get_http_response_code "$ES_LOCAL_URL" "elastic" "$ES_LOCAL_PASSWORD")
  [[ "$result" == "200" ]]
}

function uninstall_local_elastic_stack() {
  printf "yes\nno\n" | "${START_LOCAL_UNINSTALL_FILE}"
  rm -rf "${START_LOCAL_DIR}"
}

function launch_demo() {
  local platform="$1"
  if [[ "$platform" == "docker" ]]; then
    "${CURRENT_DIR}/demo.sh" docker self-hosted
    return
  fi

  docker network connect kind "$EDOT_LOCAL_CONTAINER_NAME"
  local collector_ip
  collector_ip=$(docker inspect --format '{{(index .NetworkSettings.Networks "kind").IPAddress}}' "$EDOT_LOCAL_CONTAINER_NAME")
  [[ -n "$collector_ip" ]] || return 1
  KUBE_STACK_EXTRA_VALUES_FILE=test/elastic/kube-stack-local-values.yml \
    CI=true "${CURRENT_DIR}/demo.sh" k8s "${collector_ip}:4317" "$ES_LOCAL_API_KEY"
}

function destroy_demo() {
  local platform="$1"
  echo "Destroying demo on platform: $platform"
  ${CURRENT_DIR}/demo.sh destroy "$platform"
}

# Check if a docker service is running
check_docker_service_running() {
  local container_name=$1
  local status

  # Get the container status
  status=$(docker ps --filter "name=^${container_name}$" --format '{{.Status}}' 2>/dev/null)

  # Check if container exists and is running (status starts with "Up")
  if [[ -n "$status" ]] && [[ "$status" =~ ^Up ]]; then
    echo "Container $container_name is running"
    return 0
  else
    echo "Container $container_name not running. Current status: ${status:-not found}"
    return 1
  fi
}
