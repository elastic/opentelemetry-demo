#!/bin/bash 

APP_NAME=my-otel-demo
# Check tools
tools=("helm" "kubectl")
for tool in ${tools[@]}; do
	if ! command -v $tool 2>&1 >/dev/null
	then
		echo "$tool could not be found, please install both helm and kubernetes-cli"
		exit 1
	fi
done

if [ -z "${OTEL_EXPORTER_OTLP_ENDPOINT}" ]; then
  echo "You must set OTEL_EXPORTER_OTLP_ENDPOINT to a valid URL!"
  exit 1
fi
if [ -z "${OTEL_EXPORTER_OTLP_HEADERS}" ]; then
  echo "You must set authorization headers for OTEL beginnig with Authorization="
  exit 1
fi

if [[ $OTEL_EXPORTER_OTLP_HEADERS == "Authorization=*" ]]; then
  echo "OTEL_EXPORTER_OTLP_HEADERS has invalid value \"$OTEL_EXPORTER_OTLP_HEADERS\", should start with Authorization="
  exit 1
fi

OTEL_ENDPOINT_NO_PROTO=`echo $OTEL_EXPORTER_OTLP_ENDPOINT | sed -r -e 's/^https?:\/\///'`
OTEL_AUTH_VALUE=`echo $OTEL_EXPORTER_OTLP_HEADERS | cut -d= -f2-`

kubectl delete secret elastic-secret 
kubectl create secret generic elastic-secret \
  --from-literal=elastic_apm_endpoint="$OTEL_ENDPOINT_NO_PROTO" \
  --from-literal=elastic_apm_secret_token="$OTEL_AUTH_VALUE"

if [ -z "${OTEL_DEMO_ES_ENDPOINT}" ]; then
  echo "You must set OTEL_DEMO_ES_ENDPOINT to a valid Elasticsearch URL"
  exit 1
fi
if [ -z "${OTEL_DEMO_ES_API_KEY}" ]; then
  echo "You must set OTEL_DEMO_ES_API_KEY"
  exit 1
fi

kubectl delete secret elastic-secret-ds
kubectl create secret generic elastic-secret-ds \
  --from-literal=elastic_endpoint="$OTEL_DEMO_ES_ENDPOINT" \
  --from-literal=elastic_api_key="$OTEL_DEMO_ES_API_KEY"


pushd kubernetes/elastic-helm
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update open-telemetry

helminst () {
	hcommand=upgrade
	if ! helm status $1 2>&1 > /dev/null;
	then
		echo "$1 not yet installed by helm, will install"
		hcommand=install
	else
		echo "$1 already installed, upgrading"
	fi
	helm $hcommand -f deployment.yaml $1 open-telemetry/opentelemetry-demo
}

helminst $APP_NAME
helminst otel-daemonset




cat <<-EOF
Otel demo is deployed with nginx ingress controller running.
Please add the following line to your /etc/hosts file
127.0.0.1 otel-demo.internal
Note, that for minikube and some other kubernetes distributions you may need a different IP.
For minikube this may be found with the 'minikube ip' command.

Once setup you may access the demo at
You may access it at http://otel-demo.internal
EOF