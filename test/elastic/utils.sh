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
  printf "CURRENT_DIR=%s\n" "$CURRENT_DIR"
  curl -fsSL https://elastic.co/start-local | sh -s -- --esonly
  # shellcheck source=test/elastic/bootstrap.sh
  source "${START_LOCAL_ENV_PATH}"
  sleep 2
  result=$(get_http_response_code "http://localhost:9200" "elastic" "${ES_LOCAL_PASSWORD}")
  assert_equals "200" "$result"
}

function uninstall_local_elastic_stack() {
  printf "yes\nno\n" | "${START_LOCAL_UNINSTALL_FILE}"
  rm -rf "${START_LOCAL_DIR}"
}

function launch_demo() {
  local deployment_type="$1"
  local platform="$2"
  local elasticsearch_endpoint="${ES_LOCAL_URL:-$3}"
  local elasticsearch_api_key="${ES_LOCAL_API_KEY}"
  echo "Launching demo with:"
  echo "  deployment_type: $deployment_type"
  echo "  platform: $platform"
  echo "  elasticsearch_endpoint: $elasticsearch_endpoint"
  echo "  elasticsearch_api_key: $elasticsearch_api_key"
  printf "${deployment_type}\n${platform}\n${elasticsearch_endpoint}\n${elasticsearch_api_key}\n" | ${CURRENT_DIR}/demo.sh
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
    
    local actual_name=$(docker ps -a --filter "name=${container_name}" --format '{{.Names}}' | head -1)
    if [[ -n "$actual_name" ]]; then
      bashunit::log "error" "=== Logs for $actual_name ==="
      bashunit::log "error" "$(docker logs "$actual_name" 2>&1 | tail -100)"
    else
      bashunit::log "error" "No container found matching $container_name"
      bashunit::log "error" "All containers: $(docker ps -a --format '{{.Names}}\t{{.Status}}')"
    fi

    return 1
  fi
}
