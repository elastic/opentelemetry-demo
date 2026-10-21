#!/usr/bin/env bash

set -euo pipefail

mode="${1:-all}"
if [[ $# -gt 1 || "$mode" != "docker" && "$mode" != "k8s" && "$mode" != "all" ]]; then
  echo "Usage: $0 [docker|k8s|all]" >&2
  exit 2
fi

cd "$(dirname "$0")/../.."

for command in docker python3 curl; do
  command -v "$command" >/dev/null || { echo "Required command not found: $command" >&2; exit 1; }
done
docker compose version >/dev/null
docker info >/dev/null
[[ ! -e elastic-start-local ]] || { echo "Existing elastic-start-local directory; remove it or use a separate checkout" >&2; exit 1; }

if [[ "$mode" == "k8s" || "$mode" == "all" ]]; then
  for command in kind kubectl helm; do
    command -v "$command" >/dev/null || { echo "Required command not found: $command" >&2; exit 1; }
  done
fi

if [[ "$mode" == "docker" || "$mode" == "all" ]]; then
  for container in frontend-proxy otel-collector load-generator; do
    if [[ -n "$(docker ps --filter "name=^${container}$" --format '{{.ID}}')" ]]; then
      echo "Container $container is already running; stop the existing demo before testing" >&2
      exit 1
    fi
  done
fi

export INTEGRATION_TEST_IMAGE_NAME="${INTEGRATION_TEST_IMAGE_NAME:-otel-demo-integration-tests}"
export UPSTREAM_TEST_IMAGE_NAME="${UPSTREAM_TEST_IMAGE_NAME:-otel-demo-upstream-integration-tests}"
export INTEGRATION_TEST_DEMO_VERSION="${INTEGRATION_TEST_DEMO_VERSION:-test}"

python3 -m unittest discover -s test/elastic -p test_verify_telemetry.py

IMAGE_NAME="$INTEGRATION_TEST_IMAGE_NAME" DEMO_VERSION="$INTEGRATION_TEST_DEMO_VERSION" \
  docker compose --env-file .env --env-file .env.override \
    -f compose.yaml -f compose.full.yaml -f compose.extras.yaml \
    -f docker-compose.elastic.yml build --parallel

if [[ "$mode" == "docker" || "$mode" == "all" ]]; then
  IMAGE_NAME="$UPSTREAM_TEST_IMAGE_NAME" DEMO_VERSION="$INTEGRATION_TEST_DEMO_VERSION" \
    docker compose --env-file .env \
      -f compose.yaml -f compose.full.yaml -f compose.extras.yaml \
      -f docker-compose.upstream.yml build --parallel
  python3 test/elastic/docker_mode_smoke.py
  bash test/elastic/run_integration.sh docker
fi

if [[ "$mode" == "k8s" || "$mode" == "all" ]]; then
  cluster_created=false
  kubeconfig_file=$(mktemp)
  cleanup() {
    local status=$?
    trap - EXIT
    if [[ "$cluster_created" == true ]]; then
      kind delete cluster --name chart-testing || status=1
    fi
    rm -f "$kubeconfig_file"
    exit "$status"
  }
  trap cleanup EXIT

  clusters=$(kind get clusters)
  if ! grep -Fxq chart-testing <<< "$clusters"; then
    cluster_created=true
    KUBECONFIG="$kubeconfig_file" kind create cluster --name chart-testing
  fi
  kind get kubeconfig --name chart-testing > "$kubeconfig_file"
  export KUBECONFIG="$kubeconfig_file"
  kubectl cluster-info >/dev/null
  if helm status my-otel-demo >/dev/null 2>&1 || \
     helm status opentelemetry-kube-stack -n opentelemetry-operator-system >/dev/null 2>&1; then
    echo "Demo Helm release already exists in chart-testing; refusing to replace it" >&2
    exit 1
  fi

  images=$(docker image ls "${INTEGRATION_TEST_IMAGE_NAME}:${INTEGRATION_TEST_DEMO_VERSION}-*" \
    --format '{{.Repository}}:{{.Tag}}')
  [[ -n "$images" ]] || { echo "No locally built Elastic demo images found" >&2; exit 1; }
  image_args=()
  while IFS= read -r image; do
    image_args+=("$image")
  done <<< "$images"
  kind load docker-image --name chart-testing "${image_args[@]}"

  bash test/elastic/run_integration.sh k8s
fi
