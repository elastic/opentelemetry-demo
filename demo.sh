#!/bin/sh

set -eu

# Constants
ELASTIC_STACK_VERSION="9.1.3"
ENV_OVERRIDE_FILE=".env.override"
NAMESPACE="opentelemetry-operator-system"
HELM_REPO_NAME="open-telemetry"
HELM_REPO_URL='https://open-telemetry.github.io/opentelemetry-helm-charts'

DEMO_RELEASE="my-otel-demo"
DEMO_CHART="open-telemetry/opentelemetry-demo"

KUBE_STACK_RELEASE="opentelemetry-kube-stack"
KUBE_STACK_CHART="open-telemetry/opentelemetry-kube-stack"
KUBE_STACK_VERSION='0.3.3'
KUBE_STACK_VALUES_URL_CLOUD='https://raw.githubusercontent.com/elastic/elastic-agent/refs/tags/v'$ELASTIC_STACK_VERSION'/deploy/helm/edot-collector/kube-stack/values.yaml'
KUBE_STACK_VALUES_URL_SERVERLESS='https://raw.githubusercontent.com/elastic/elastic-agent/refs/tags/v'$ELASTIC_STACK_VERSION'/deploy/helm/edot-collector/kube-stack/managed_otlp/values.yaml'
SECRET_NAME='elastic-secret-otel'

DOCKER_COLLECTOR_CONFIG_CLOUD='./src/otel-collector/otelcol-elastic-config.yaml'
DOCKER_COLLECTOR_CONFIG_SERVERLESS='./src/otel-collector/otelcol-elastic-otlp-config.yaml'
COLLECTOR_CONTRIB_IMAGE=docker.elastic.co/elastic-agent/elastic-agent:$ELASTIC_STACK_VERSION


# Variables
ELASTIC_DEPLOYMENT_TYPE=""
PLATFORM=""
DESTROY="false"
ELASTICSEARCH_ENDPOINT=""
ELASTICSEARCH_API_KEY=""

usage() {
    echo "Usage: $0 [cloud-hosted|serverless] [docker|k8s] | destroy [docker|k8s]"
    exit 1
}

parse_args() {
  if [ $# -eq 0 ]; then
    usage
  fi

  if [ "$1" = "destroy" ]; then
    DESTROY="true"
    if [ $# -ge 2 ]; then
      PLATFORM="$2"
    fi
    return
  fi

  ELASTIC_DEPLOYMENT_TYPE="$1"
  if [ $# -ge 2 ]; then
    PLATFORM="$2"
  fi
}

update_env_var() {
  VAR="$1"
  VAL="$2"
  if grep -q "^$VAR=" "$ENV_OVERRIDE_FILE"; then
    sed -i '' "s|^$VAR=.*|$VAR=\"$VAL\"|" "$ENV_OVERRIDE_FILE"
  else
    echo "$VAR=\"$VAL\"" >> "$ENV_OVERRIDE_FILE"
  fi
}

ensure_env_values() {
  if [ -z "$ELASTICSEARCH_ENDPOINT" ]; then
    printf "Enter your Elastic endpoint: "
    read ELASTICSEARCH_ENDPOINT
  fi

  if [ -z "$ELASTICSEARCH_API_KEY" ]; then
    printf "Enter your Elastic API key: "
    read ELASTICSEARCH_API_KEY
  fi
}

# Resolve OTEL Collector config path for Docker based on ELASTIC_DEPLOYMENT_TYPE
set_docker_collector_config() {
  case "$ELASTIC_DEPLOYMENT_TYPE" in
    cloud-hosted)
      OTEL_COLLECTOR_CONFIG=$DOCKER_COLLECTOR_CONFIG_CLOUD
      ;;
    serverless)
      OTEL_COLLECTOR_CONFIG=$DOCKER_COLLECTOR_CONFIG_SERVERLESS
      ;;
  esac
}

start_docker() {
  set_docker_collector_config
  ensure_env_values

  update_env_var "ELASTICSEARCH_ENDPOINT" "$ELASTICSEARCH_ENDPOINT"
  update_env_var "ELASTICSEARCH_API_KEY" "$ELASTICSEARCH_API_KEY"
  update_env_var "OTEL_COLLECTOR_CONFIG" "$OTEL_COLLECTOR_CONFIG"
  update_env_var "COLLECTOR_CONTRIB_IMAGE" "$COLLECTOR_CONTRIB_IMAGE"

  make start
}

ensure_k8s_prereqs() {
  helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL" --force-update
  if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    kubectl create namespace "$NAMESPACE"
  fi
}

apply_k8s_secret() {
  ensure_env_values
  case "$ELASTIC_DEPLOYMENT_TYPE" in
    cloud-hosted)
      kubectl create secret generic "$SECRET_NAME" \
        --namespace "$NAMESPACE" \
        --from-literal=elastic_endpoint="$ELASTICSEARCH_ENDPOINT" \
        --from-literal=elastic_api_key="$ELASTICSEARCH_API_KEY" \
        --dry-run=client -o yaml | kubectl apply -f -
      ;;
    serverless)
      kubectl create secret generic "$SECRET_NAME" \
        --namespace "$NAMESPACE" \
        --from-literal=elastic_otlp_endpoint="$ELASTICSEARCH_ENDPOINT" \
        --from-literal=elastic_api_key="$ELASTICSEARCH_API_KEY" \
        --dry-run=client -o yaml | kubectl apply -f -
      ;;
  esac
}

install_kube_stack() {
  case "$ELASTIC_DEPLOYMENT_TYPE" in
    cloud-hosted)
      VALUES_URL="$KUBE_STACK_VALUES_URL_CLOUD"
      ;;
    serverless)
      VALUES_URL="$KUBE_STACK_VALUES_URL_SERVERLESS"
      ;;
  esac

  helm upgrade --install "$KUBE_STACK_RELEASE" "$KUBE_STACK_CHART" \
    --namespace "$NAMESPACE" \
    --values "$VALUES_URL" \
    --version "$KUBE_STACK_VERSION"
}

install_demo_chart() {
  helm upgrade --install "$DEMO_RELEASE" "$DEMO_CHART" -f kubernetes/elastic-helm/demo.yml
}

start_k8s() {
  ensure_k8s_prereqs
  apply_k8s_secret
  install_kube_stack
  install_demo_chart
}

destroy_docker() {
  make stop
}

destroy_k8s() {
  helm uninstall "$DEMO_RELEASE" --ignore-not-found
  helm uninstall "$KUBE_STACK_RELEASE" -n "$NAMESPACE" --ignore-not-found
  kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" --ignore-not-found
  kubectl delete namespace "$NAMESPACE" --ignore-not-found --wait=false --timeout=60s
}

main() {
  parse_args "$@"

  if [ "$DESTROY" = "true" ]; then
    if [ -z "$PLATFORM" ]; then
      echo "Destroying Docker and Kubernetes resources..."
      destroy_docker
      destroy_k8s
      echo "Done! Destroyed Docker and Kubernetes resources."
      return 0
    fi

    if [ "$PLATFORM" = "docker" ]; then
      echo "Destroying Docker resources..."
      destroy_docker
      echo "Done! Destroyed Docker resources."
      return 0
    fi

    if [ "$PLATFORM" = "k8s" ]; then
      echo "Destroying Kubernetes resources..."
      destroy_k8s
      echo "Done! Destroyed Kubernetes resources."
      return 0
    fi

    usage
  fi

  if [ "$ELASTIC_DEPLOYMENT_TYPE" != "cloud-hosted" ] && [ "$ELASTIC_DEPLOYMENT_TYPE" != "serverless" ]; then
    usage
  fi

  if [ "$PLATFORM" != "docker" ] && [ "$PLATFORM" != "k8s" ]; then
    usage
  fi

  echo "Starting '$ELASTIC_DEPLOYMENT_TYPE' on '$PLATFORM'..."
  if [ "$PLATFORM" = "docker" ]; then
    start_docker
  else
    start_k8s
  fi
  echo "Done! '$ELASTIC_DEPLOYMENT_TYPE' started on '$PLATFORM'."
}

main "$@"