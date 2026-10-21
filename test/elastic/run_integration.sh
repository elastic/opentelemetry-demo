#!/usr/bin/env bash

set -euo pipefail

mode="${1:?Usage: $0 docker|k8s}"
[[ "$mode" == "docker" || "$mode" == "k8s" ]] || exit 2

CURRENT_DIR=$(cd "$(dirname "$0")/../.." && pwd)
cd "$CURRENT_DIR"
START_LOCAL_DIR="$CURRENT_DIR/elastic-start-local"
START_LOCAL_ENV_PATH="$START_LOCAL_DIR/.env"
START_LOCAL_UNINSTALL_FILE="$START_LOCAL_DIR/uninstall.sh"
source "$CURRENT_DIR/test/elastic/utils.sh"
[[ ! -e "$START_LOCAL_DIR" ]] || { echo "Existing start-local directory: $START_LOCAL_DIR" >&2; exit 1; }

env_backup=$(mktemp)
cp .env.override "$env_backup"

started=false
deployed=false
port_forward_pid=""
port_forward_log=""

diagnostics() {
  if [[ "$mode" == "docker" ]]; then
    docker compose --env-file .env --env-file .env.override \
      -f compose.yaml -f compose.full.yaml -f compose.extras.yaml \
      -f docker-compose.elastic.yml -f docker-compose.elastic-self-hosted.yml ps || true
    docker compose --env-file .env --env-file .env.override \
      -f compose.yaml -f compose.full.yaml -f compose.extras.yaml \
      -f docker-compose.elastic.yml -f docker-compose.elastic-self-hosted.yml \
      logs --tail=40 frontend frontend-proxy checkout otel-collector load-generator \
      payment quote shipping product-catalog recommendation || true
  else
    if [[ -n "$port_forward_log" ]]; then
      cat "$port_forward_log" || true
    fi
    kubectl get pods -A -o wide || true
    kubectl get events -A --sort-by=.lastTimestamp | tail -100 || true
    kubectl describe pods -l app.kubernetes.io/part-of=opentelemetry-demo || true
    kubectl logs deployment/frontend-proxy --tail=80 || true
    kubectl logs deployment/frontend --tail=80 || true
    kubectl logs deployment/load-generator --tail=80 || true
    kubectl logs deployment/checkout --tail=80 || true
    kubectl logs deployment/product-catalog --tail=80 || true
    kubectl logs deployment/shipping --tail=80 || true
    kubectl logs -n opentelemetry-operator-system \
      deployment/opentelemetry-kube-stack-gateway-collector --tail=80 || true
    kubectl logs -n opentelemetry-operator-system \
      daemonset/opentelemetry-kube-stack-daemon-collector --tail=80 || true
  fi
}

cleanup() {
  local status=$?
  trap - EXIT
  if (( status != 0 )); then
    diagnostics
  fi
  if [[ -n "$port_forward_pid" ]]; then
    kill "$port_forward_pid" 2>/dev/null || true
    wait "$port_forward_pid" 2>/dev/null || true
  fi
  if [[ -n "$port_forward_log" ]]; then
    rm -f "$port_forward_log"
  fi
  if [[ "$deployed" == true ]]; then
    destroy_demo "$mode" || true
  fi
  if [[ "$started" == true && -x "$START_LOCAL_UNINSTALL_FILE" ]]; then
    uninstall_local_elastic_stack || true
  fi
  cp "$env_backup" .env.override
  rm -f "$env_backup"
  exit "$status"
}
trap cleanup EXIT

started=true
start_local_elastic_stack

if [[ "$mode" == "docker" ]]; then
  export IMAGE_NAME="${INTEGRATION_TEST_IMAGE_NAME:-otel-demo-integration-tests}"
  export DEMO_VERSION="${INTEGRATION_TEST_DEMO_VERSION:-test}"
  export LOCUST_USERS=1
  export LOCUST_BROWSER_USER_WEIGHT=0
  deployed=true
  launch_demo docker
  deadline=$((SECONDS + 300))
  until check_docker_service_running load-generator \
    && check_docker_service_running otel-collector \
    && [[ "$(docker inspect --format '{{.State.Health.Status}}' product-catalog 2>/dev/null)" == "healthy" ]] \
    && [[ "$(docker inspect --format '{{.State.Health.Status}}' checkout 2>/dev/null)" == "healthy" ]] \
    && curl -fsS --max-time 5 -o /dev/null http://localhost:8080/; do
    (( SECONDS < deadline )) || { echo "Docker demo did not become ready" >&2; exit 1; }
    sleep 3
  done
  export ELASTIC_TEST_FRONTEND_URL=http://localhost:8080
else
  export DEMO_HELM_IMAGE_REPOSITORY="${INTEGRATION_TEST_IMAGE_NAME:-otel-demo-integration-tests}"
  export DEMO_HELM_IMAGE_TAG="${INTEGRATION_TEST_DEMO_VERSION:-test}"
  deployed=true
  launch_demo k8s
  kubectl rollout status -n opentelemetry-operator-system \
    deployment/opentelemetry-kube-stack-opentelemetry-operator --timeout=600s
  deadline=$((SECONDS + 600))
  until kubectl get -n opentelemetry-operator-system \
    deployment/opentelemetry-kube-stack-gateway-collector >/dev/null 2>&1 \
    && kubectl get -n opentelemetry-operator-system \
      daemonset/opentelemetry-kube-stack-daemon-collector >/dev/null 2>&1; do
    (( SECONDS < deadline )) || { echo "Elastic collector workloads were not created" >&2; exit 1; }
    sleep 3
  done
  kubectl rollout status -n opentelemetry-operator-system \
    deployment/opentelemetry-kube-stack-gateway-collector --timeout=600s
  kubectl rollout status -n opentelemetry-operator-system \
    daemonset/opentelemetry-kube-stack-daemon-collector --timeout=600s
  kubectl rollout status deployment/frontend-proxy --timeout=600s
  kubectl rollout status deployment/load-generator --timeout=600s
  kubectl rollout status deployment/product-catalog --timeout=600s
  kubectl rollout status deployment/checkout --timeout=600s
  python3 test/elastic/verify_k8s_images.py
  port_forward_log=$(mktemp)
  kubectl port-forward service/frontend-proxy 18080:8080 >"$port_forward_log" 2>&1 &
  port_forward_pid=$!
  deadline=$((SECONDS + 60))
  until curl -fsS --max-time 5 -o /dev/null http://localhost:18080/; do
    kill -0 "$port_forward_pid" 2>/dev/null || { echo "Kubernetes port-forward stopped" >&2; exit 1; }
    (( SECONDS < deadline )) || { echo "Kubernetes frontend proxy did not become reachable" >&2; exit 1; }
    sleep 2
  done
  export ELASTIC_TEST_FRONTEND_URL=http://localhost:18080
fi

python3 test/elastic/verify_telemetry.py
