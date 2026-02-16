#!/bin/sh

set -eu

# Constants
ELASTIC_STACK_VERSION="9.3.0"
ENV_OVERRIDE_FILE=".env.override"
NAMESPACE="opentelemetry-operator-system"
HELM_REPO_NAME="open-telemetry"
HELM_REPO_URL='https://open-telemetry.github.io/opentelemetry-helm-charts'

DEMO_RELEASE="my-otel-demo"
DEMO_CHART="open-telemetry/opentelemetry-demo"
DEMO_HELM_VERSION='0.38.6'

KUBE_STACK_RELEASE="opentelemetry-kube-stack"
KUBE_STACK_CHART="open-telemetry/opentelemetry-kube-stack"
KUBE_STACK_VERSION='0.12.4'
KUBE_STACK_VALUES_URL_CLOUD='https://raw.githubusercontent.com/elastic/elastic-agent/refs/tags/v'$ELASTIC_STACK_VERSION'/deploy/helm/edot-collector/kube-stack/values.yaml'
KUBE_STACK_VALUES_URL_SERVERLESS='https://raw.githubusercontent.com/elastic/elastic-agent/refs/tags/v'$ELASTIC_STACK_VERSION'/deploy/helm/edot-collector/kube-stack/managed_otlp/values.yaml'
SECRET_NAME='elastic-secret-otel'

DOCKER_COLLECTOR_CONFIG_CLOUD='./src/otel-collector/otelcol-elastic-config.yaml'
DOCKER_COLLECTOR_CONFIG_SERVERLESS='./src/otel-collector/otelcol-elastic-otlp-config.yaml'
COLLECTOR_CONTRIB_IMAGE=docker.elastic.co/elastic-agent/elastic-agent:$ELASTIC_STACK_VERSION

# Detect sed variant: GNU sed uses --version, BSD sed doesn't
# GNU sed: sed -i (no empty string needed)
# BSD sed: sed -i '' (empty string required)
if sed --version >/dev/null 2>&1; then
  SED_IS_BSD="false"
else
  SED_IS_BSD="true"
fi

# Portable sed in-place editing function
# Usage: sed_in_place "s/pattern/replacement/g" file
sed_in_place() {
  if [ "$SED_IS_BSD" = "true" ]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Variables
deployment_type=""
platform=""
destroy="false"
elasticsearch_endpoint=""
elasticsearch_api_key=""

usage() {
  echo "Run the script with no arguments. This will start an interactive prompt that will guide you through the setup of the Elastic OpenTelemetry Demo."
  echo
  echo "To destroy the demo, run: $0 destroy [docker|k8s]"
  echo "  - pass 'docker' or 'k8s' to destroy only that platform"
  echo "  - omit the platform to destroy both docker and k8s resources"
  exit 1
}

parse_args() {
  if [ $# -eq 4 ]; then
    deployment_type="$1"
    platform="$2"
    elasticsearch_endpoint="$3"
    elasticsearch_api_key="$4"
    return
  fi

  if [ $# -eq 0 ]; then

    while true; do
      echo
      printf "❓ Which Elasticsearch deployment type do you want to send the data into? [serverless/cloud-hosted]? "
      read -r deployment_type
      case "$deployment_type" in
      cloud-hosted | serverless) break ;;
      *) echo "Please enter 'cloud-hosted' or 'serverless'." ;;
      esac
    done

    while true; do
      echo
      printf "❓ In which environment the demo should be deployed? [docker/k8s]? "
      read -r platform
      case "$platform" in
      docker | k8s) break ;;
      *) echo "Please enter 'docker' or 'k8s'." ;;
      esac
    done
    return
  fi

  if [ "$1" = "destroy" ]; then
    destroy="true"
    if [ $# -ge 2 ]; then
      platform="$2"
    fi
    return
  fi
  usage
}

update_env_var() {
  VAR="$1"
  VAL="$2"
  tmp=$(mktemp) || exit 1

  if grep -q "^$VAR=" "$ENV_OVERRIDE_FILE"; then
    sed_in_place "s|^$VAR=.*|$VAR=\"$VAL\"|" "$ENV_OVERRIDE_FILE"
  else
    echo "$VAR=\"$VAL\"" >>"$ENV_OVERRIDE_FILE"
  fi
}

# Read a secret from the terminal without echo and assign it to a variable by name
# Usage: read_secret variable_name "Prompt: "
read_secret() {
  var_name="$1"
  prompt="$2"
  printf "%s" "$prompt"
  stty -echo 2>/dev/null || :
  trap 'stty echo 2>/dev/null' 0 INT TERM HUP
  read -r "${var_name?}"
  stty echo 2>/dev/null || :
  trap - 0 INT TERM HUP
  echo
}

ensure_env_values() {
  if [ -n "${CI:-}" ]; then
    return 0
  fi

  echo
  if ! check_existing_credentials; then
    if [ -z "$elasticsearch_endpoint" ]; then
      if [ "$deployment_type" = "serverless" ]; then
        printf "🔑 Enter your Elastic OTLP endpoint: "
      else
        printf "🔑 Enter your Elastic endpoint: "
      fi
      read -r elasticsearch_endpoint
    fi
  fi

  if [ -z "$elasticsearch_api_key" ]; then
    read_secret elasticsearch_api_key "🔑 Enter your Elastic API key: "
  fi
  echo
}

# Resolve OTEL Collector config path for Docker based on deployment_type
set_docker_collector_config() {
  case "$deployment_type" in
  cloud-hosted)
    OTEL_COLLECTOR_CONFIG=$DOCKER_COLLECTOR_CONFIG_CLOUD
    ;;
  serverless)
    OTEL_COLLECTOR_CONFIG=$DOCKER_COLLECTOR_CONFIG_SERVERLESS
    ;;
  esac
}

check_existing_credentials() {
  if [ ! -f "$ENV_OVERRIDE_FILE" ]; then
    return 1
  fi

  elasticsearch_endpoint=$(grep "^ELASTICSEARCH_ENDPOINT=" "$ENV_OVERRIDE_FILE" | cut -d'=' -f2- | tr -d '"')
  elasticsearch_api_key=$(grep "^ELASTICSEARCH_API_KEY=" "$ENV_OVERRIDE_FILE" | cut -d'=' -f2- | tr -d '"')

  if [ -n "$elasticsearch_endpoint" ] && [ -n "$elasticsearch_api_key" ] &&
    [ "$elasticsearch_endpoint" != "YOUR_ENDPOINT" ] &&
    [ "$elasticsearch_api_key" != "YOUR_API_KEY" ]; then
    echo "✅ Using existing credentials from $ENV_OVERRIDE_FILE"
    return 0
  fi

  elasticsearch_endpoint=""
  elasticsearch_api_key=""
  return 1
}

start_docker() {
  set_docker_collector_config
  ensure_env_values

  update_env_var "ELASTICSEARCH_ENDPOINT" "$elasticsearch_endpoint"
  update_env_var "ELASTICSEARCH_API_KEY" "$elasticsearch_api_key"
  update_env_var "OTEL_COLLECTOR_CONFIG" "$OTEL_COLLECTOR_CONFIG"
  update_env_var "COLLECTOR_CONTRIB_IMAGE" "$COLLECTOR_CONTRIB_IMAGE"

  export ELASTICSEARCH_ENDPOINT="$elasticsearch_endpoint"
  export ELASTICSEARCH_API_KEY="$elasticsearch_api_key"

  make start
}

ensure_k8s_prereqs() {
  helm repo add "$HELM_REPO_NAME" "$HELM_REPO_URL" --force-update
  kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
}

apply_k8s_secret() {
  ensure_env_values
  case "$deployment_type" in
  cloud-hosted)
    kubectl create secret generic "$SECRET_NAME" \
      --namespace "$NAMESPACE" \
      --from-literal=elastic_endpoint="$elasticsearch_endpoint" \
      --from-literal=elastic_api_key="$elasticsearch_api_key" \
      --dry-run=client -o yaml | kubectl apply -f -
    ;;
  serverless)
    kubectl create secret generic "$SECRET_NAME" \
      --namespace "$NAMESPACE" \
      --from-literal=elastic_otlp_endpoint="$elasticsearch_endpoint" \
      --from-literal=elastic_api_key="$elasticsearch_api_key" \
      --dry-run=client -o yaml | kubectl apply -f -
    ;;
  esac
}

install_kube_stack() {
  case "$deployment_type" in
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
  helm upgrade --install "$DEMO_RELEASE" "$DEMO_CHART" --version "$DEMO_HELM_VERSION" -f kubernetes/elastic-helm/demo.yml
}

start_k8s() {
  ensure_k8s_prereqs
  apply_k8s_secret
  install_kube_stack
  install_demo_chart
}

destroy_docker() {
  echo
  make stop
  echo
}

destroy_k8s() {
  echo
  helm uninstall "$DEMO_RELEASE" --ignore-not-found
  helm uninstall "$KUBE_STACK_RELEASE" -n "$NAMESPACE" --ignore-not-found
  kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE" --ignore-not-found
  kubectl delete namespace "$NAMESPACE" --ignore-not-found --wait=false --timeout=60s
  echo
}

main() {
  echo '----------------------------------------------------'
  echo '🚀 OpenTelemetry Demo with Elastic Observability'
  echo '----------------------------------------------------'

  parse_args "$@"

  if [ "$destroy" = "true" ]; then
    if [ -z "$platform" ]; then
      echo "⌛️ Destroying Docker and Kubernetes resources..."
      destroy_docker
      destroy_k8s
      echo "✅ Done! Destroyed Docker and Kubernetes resources."
      exit 0
    fi

    if [ "$platform" = "docker" ]; then
      echo "⌛️ Destroying Docker resources..."
      destroy_docker
      echo "✅ Done! Destroyed Docker resources."
      exit 0
    fi

    if [ "$platform" = "k8s" ]; then
      echo "⌛️ Destroying Kubernetes resources..."
      destroy_k8s
      echo "✅ Done! Destroyed Kubernetes resources."
      exit 0
    fi

    usage
  fi

  if [ "$deployment_type" != "cloud-hosted" ] && [ "$deployment_type" != "serverless" ]; then
    usage
  fi

  if [ "$platform" != "docker" ] && [ "$platform" != "k8s" ]; then
    usage
  fi

  echo
  echo "⌛️ Starting OTel Demo + EDOT on '$platform' → Elastic ($deployment_type)..."

  if [ "$platform" = "docker" ]; then
    start_docker
  else
    start_k8s
  fi
  echo
  echo "🎉 OTel Demo and EDOT are running on '$platform'; data is flowing to Elastic ($deployment_type)."
}

main "$@"
