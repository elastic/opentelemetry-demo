#!/bin/sh

set -eux

ENV_OVERRIDE_FILE=".env.override"

SCENARIO=""
PLATFORM=""
ELASTICSEARCH_ENDPOINT=""
ELASTICSEARCH_API_KEY=""

usage() {
    echo "Usage: $0 --scenario [cloud-hosted|serverless] --platform [docker|k8s]"
    exit 1
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --scenario)
        SCENARIO="$2"
        shift 2
        ;;
      --platform)
        PLATFORM="$2"
        shift 2
        ;;
      *)
        echo "Unknown argument: $1"
        usage
        ;;
    esac
  done
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

parse_args "$@"

if [ "$SCENARIO" != "cloud-hosted" ] && [ "$SCENARIO" != "serverless" ]; then
  usage
fi

if [ "$PLATFORM" != "docker" ] && [ "$PLATFORM" != "k8s" ]; then
  usage
fi

echo "Starting '$SCENARIO' scenario on '$PLATFORM'..."

if [ "$PLATFORM" = "docker" ]; then
  case "$SCENARIO" in
    cloud-hosted)
      OTEL_COLLECTOR_CONFIG=./src/otel-collector/otelcol-elastic-config.yaml
      ;;
    serverless)
      OTEL_COLLECTOR_CONFIG=./src/otel-collector/otelcol-elastic-otlp-config.yaml
      ;;
  esac

  if [ -z "$ELASTICSEARCH_ENDPOINT" ]; then
    printf "Enter your Elastic endpoint: "
    read ELASTICSEARCH_ENDPOINT
  fi

  if [ -z "$ELASTICSEARCH_API_KEY" ]; then
    printf "Enter your Elastic API key: "
    read ELASTICSEARCH_API_KEY
  fi

  update_env_var "ELASTICSEARCH_ENDPOINT" "$ELASTICSEARCH_ENDPOINT"
  update_env_var "ELASTICSEARCH_API_KEY" "$ELASTICSEARCH_API_KEY"
  update_env_var "OTEL_COLLECTOR_CONFIG" "$OTEL_COLLECTOR_CONFIG"

  make start
elif [ "$PLATFORM" = "k8s" ]; then
  helm repo add open-telemetry 'https://open-telemetry.github.io/opentelemetry-helm-charts' --force-update
  kubectl create namespace opentelemetry-operator-system
  if [ -z "$ELASTICSEARCH_ENDPOINT" ]; then
    printf "Enter your Elastic endpoint: "
    read ELASTICSEARCH_ENDPOINT
  fi

  if [ -z "$ELASTICSEARCH_API_KEY" ]; then
    printf "Enter your Elastic API key: "
    read ELASTICSEARCH_API_KEY
  fi
  case "$SCENARIO" in
    cloud-hosted)
      kubectl create secret generic elastic-secret-otel \
      --namespace opentelemetry-operator-system \
      --from-literal=elastic_endpoint="$ELASTICSEARCH_ENDPOINT" \
      --from-literal=elastic_api_key="$ELASTICSEARCH_API_KEY"

      helm install opentelemetry-kube-stack open-telemetry/opentelemetry-kube-stack \
      --namespace opentelemetry-operator-system \
      --values 'https://raw.githubusercontent.com/elastic/elastic-agent/refs/tags/v9.1.3/deploy/helm/edot-collector/kube-stack/values.yaml' \
      --version '0.3.3'
      ;;
    serverless)
      
      kubectl create secret generic elastic-secret-otel \
      --namespace opentelemetry-operator-system \
      --from-literal=elastic_otlp_endpoint="$ELASTICSEARCH_ENDPOINT" \
      --from-literal=elastic_api_key="$ELASTICSEARCH_API_KEY"

      helm install opentelemetry-kube-stack open-telemetry/opentelemetry-kube-stack \
      --namespace opentelemetry-operator-system \
      --values 'https://raw.githubusercontent.com/elastic/elastic-agent/refs/tags/v9.1.3/deploy/helm/edot-collector/kube-stack/managed_otlp/values.yaml' \
      --version '0.3.3'
      ;;
  esac
  helm install my-otel-demo open-telemetry/opentelemetry-demo -f kubernetes/elastic-helm/demo.yml
fi

echo "Done! '$SCENARIO' started on '$PLATFORM'."