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
  echo "=== STARTING LOCAL ELASTIC STACK ==="
  printf "CURRENT_DIR=%s\n" "$CURRENT_DIR"

  echo "Downloading and running elastic start-local script..."
  if ! curl -fsSL https://elastic.co/start-local | sh; then
    echo "ERROR: Failed to start local Elastic stack"
    echo "Curl exit code: $?"
    return 1
  fi

  echo "Sourcing environment variables..."
  # shellcheck source=test/elastic/bootstrap.sh
  if ! source "${START_LOCAL_ENV_PATH}"; then
    echo "ERROR: Failed to source ${START_LOCAL_ENV_PATH}"
    return 1
  fi

  echo "Waiting for Elasticsearch to be ready..."
  sleep 2

  echo "Testing Elasticsearch connectivity..."
  result=$(get_http_response_code "http://localhost:9200" "elastic" "${ES_LOCAL_PASSWORD}")
  echo "Elasticsearch response code: $result"

  if [[ "$result" != "200" ]]; then
    echo "ERROR: Elasticsearch not responding correctly"
    echo "Expected: 200, Got: $result"
    echo "Environment variables:"
    env | grep ES_ || echo "No ES_ variables found"
    return 1
  fi

  assert_equals "200" "$result"
  echo "Local Elastic stack started successfully"
}

function uninstall_local_elastic_stack() {
  echo "=== UNINSTALLING LOCAL ELASTIC STACK ==="
  printf "yes\nno\n" | "${START_LOCAL_UNINSTALL_FILE}"
  rm -rf "${START_LOCAL_DIR}"
  echo "Local Elastic stack uninstalled"
}

function launch_demo() {
  local deployment_type="$1"
  local platform="$2"
  local elasticsearch_endpoint="${ES_LOCAL_URL:-$3}"
  local elasticsearch_api_key="${ES_LOCAL_API_KEY}"

  echo "=== LAUNCHING DEMO ==="
  echo "  deployment_type: $deployment_type"
  echo "  platform: $platform"
  echo "  elasticsearch_endpoint: $elasticsearch_endpoint"
  echo "  elasticsearch_api_key: ${elasticsearch_api_key:0:10}..."
  echo "========================"

  # Check if demo.sh exists
  if [[ ! -f "${CURRENT_DIR}/demo.sh" ]]; then
    echo "ERROR: demo.sh not found at ${CURRENT_DIR}/demo.sh"
    return 1
  fi

  # Run demo.sh with error capture
  if ! printf "${deployment_type}\n${platform}\n${elasticsearch_endpoint}\n${elasticsearch_api_key}\n" | "${CURRENT_DIR}/demo.sh"; then
    echo "ERROR: demo.sh execution failed"
    echo "Exit code: $?"
    echo "Checking Docker containers status:"
    docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
    return 1
  fi

  echo "Demo launch completed successfully"
}

function destroy_demo() {
  local platform="$1"
  echo "=== DESTROYING DEMO ==="
  echo "Destroying demo on platform: $platform"

  if ! "${CURRENT_DIR}/demo.sh" destroy "$platform"; then
    echo "ERROR: Failed to destroy demo on $platform"
    echo "Exit code: $?"
    return 1
  fi

  echo "Demo destruction completed successfully"
}

# Check if a docker service is running
check_docker_service_running() {
  local container_name=$1
  local status

  echo "Checking container: $container_name"

  # Get the container status with more details
  status=$(docker ps --filter "name=^${container_name}$" --format '{{.Status}}' 2>/dev/null)

  if [[ -n "$status" ]] && [[ "$status" =~ ^Up ]]; then
    echo "  Container $container_name is running: $status"
    return 0
  else
    echo "  Container $container_name not running"
    echo "  Expected status: Up*"
    echo "  Actual status: ${status:-not found}"

    # Show container details if it exists
    local container_info=$(docker ps -a --filter "name=^${container_name}$" --format '{{.Status}}\t{{.Image}}\t{{.Ports}}' 2>/dev/null)
    if [[ -n "$container_info" ]]; then
      echo "     Container details: $container_info"
      echo "     Recent logs:"
      docker logs "$container_name" --tail 5 2>&1 || echo "     No logs available"
    else
      echo "     Container does not exist"
    fi
    return 1
  fi
}
