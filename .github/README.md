<!-- markdownlint-disable-next-line -->

# <img src="https://opentelemetry.io/img/logos/opentelemetry-logo-nav.png" alt="OTel logo" width="32"> :heavy_plus_sign: <img src="https://images.contentstack.io/v3/assets/bltefdd0b53724fa2ce/blt601c406b0b5af740/620577381692951393fdf8d6/elastic-logo-cluster.svg" alt="OTel logo" width="32"> OpenTelemetry Demo with Elastic Observability

The following guide describes how to setup the OpenTelemetry demo with Elastic Observability using [Docker compose](#docker-compose) or [Kubernetes](#kubernetes). This fork introduces several changes to the agents used in the demo:

- The Java agent within the [Ad](../src/adservice/Dockerfile.elastic), the [Fraud Detection](../src/frauddetectionservice/Dockerfile.elastic) and the [Kafka](../src/kafka/Dockerfile.elastic) services have been replaced with the Elastic distribution of the OpenTelemetry Java Agent. You can find more information about the Elastic distribution in [this blog post](https://www.elastic.co/observability-labs/blog/elastic-distribution-opentelemetry-java-agent).
- The .NET agent within the [Cart service](../src/cartservice/src/Directory.Build.props) has been replaced with the Elastic distribution of the OpenTelemetry .NET Agent. You can find more information about the Elastic distribution in [this blog post](https://www.elastic.co/observability-labs/blog/elastic-opentelemetry-distribution-dotnet-applications).
- The Elastic distribution of the OpenTelemetry Node.js Agent has replaced the OpenTelemetry Node.js agent in the [Payment service](../src/paymentservice/package.json). Additional details about the Elastic distribution are available in [this blog post](https://www.elastic.co/observability-labs/blog/elastic-opentelemetry-distribution-node-js).
- The Elastic distribution for OpenTelemetry Python has replaced the OpenTelemetry Python agent in the [Recommendation service](..src/recommendationservice/requirements.txt). Additional details about the Elastic distribution are available in [this blog post](https://www.elastic.co/observability-labs/blog/elastic-opentelemetry-distribution-python).

Additionally, the OpenTelemetry Contrib collector has also been changed to the [Elastic OpenTelemetry Collector distribution](https://github.com/elastic/elastic-agent/blob/main/internal/pkg/otel/README.md). This ensures a more integrated and optimized experience with Elastic Observability.

## Root cause analysis workshop

The OpenTelemetry Root Cause Analysis (RCA) workshop is designed to identify the underlying causes of incidents or issues within a system instrumented with OpenTelemetry. The goal is to understand why the issue occurred, prevent recurrence, and improve overall system reliability. The workshop was set up to simulate a real-world environment by deploying the OpenTelemetry Demo with the following custom modifications:

- **Ingress controller:** Many of our users have logs from nginx ingress controllers. We are, initially, focusing around this as a requirement since it is a rich source of logs data.
- **Uninstrumented services**: We will initially disable traces from the Ad Service and Product Catalog Service to better simulate real world situations in which tracing is not always available.

### Prerequisites:

On a mac you can easily install these prerequisites with: `brew install minikube helm kubernetes-cli`

- Create a Kubernetes cluster. For local development `minikube` is recommended. There are no specific requirements, so you can create a local one, or use a managed Kubernetes cluster, such as [GKE](https://cloud.google.com/kubernetes-engine), [EKS](https://aws.amazon.com/eks/), or [AKS](https://azure.microsoft.com/en-us/products/kubernetes-service).
- Set up [kubectl](https://kubernetes.io/docs/reference/kubectl/).
- Set up [Helm](https://helm.sh/).
- Install the Nginx Ingress Controller:
- Set up [Minikube](https://minikube.sigs.k8s.io/docs/)

```
helm install --namespace kube-system nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx
```

## Fast Track Startup

The fast way to set things up is with the `elastic-setup` script. This assumes and requires `minikube`. Before running it set the following environment variables:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT="https://YOUR_APM_SERVER_ENDPOINT"
export OTEL_EXPORTER_OTLP_HEADERS="Authorization=ApiKey YOUR_APM_API_KEY"
export OTEL_DEMO_ES_ENDPOINT="https://YOUR_ES_URL"
export OTEL_DEMO_ES_API_KEY="YOUR_ES_API_KEY"
export KIBANA_URL="HTTP://URL/FOR/KIBANA"
# Get from the kibana management UI
export KIBANA_API_KEY="YOURAPIKEY"

# Create a fleet policy (for a synthetics private location) and go through the "add agent" flow for it. Within the policy go through the add agent flow and get these values from there
set -x OTEL_DEMO_FLEET_URL "https://FLEET_URL"
set -x OTEL_DEMO_FLEET_ENROLLMENT_TOKEN "YOURTOKEN"

# Get the synthetics API key from the "Project API Key" page in the Synthetics Kibana app
export SYNTHETICS_API_KEY="YOURSYNTHETICSAPIKEYI"
# Make sure to create a synthetics private location in the synthetics UI linked to the previously created fleet policy. It should generally be named otel-demo, but you can change it here
export SYNTHETICS_PRIVATE_LOCATION="otel-demo"

```

Then, after loading them into your shell run `./elastic-setup`

You are now done! If you'd like to set things up manually see the "Manual Startup" section below.

## Manual Startup

If you'd rather not use the "Fast Track" startup follow these instructions.

### Start the Demo

1. Setup Elastic Observability on Elastic Cloud.
2. Create a secret in Kubernetes with the following command.
   ```
   kubectl create secret generic elastic-secret \
     --from-literal=elastic_apm_endpoint='YOUR_APM_ENDPOINT_WITHOUT_HTTPS_PREFIX' \
     --from-literal=elastic_apm_secret_token='Bearer YOUR_APM_SECRET_TOKEN'
   ```
   Don't forget to replace
   <<<<<<< HEAD
   - `YOUR_APM_ENDPOINT_WITHOUT_HTTPS_PREFIX`: your Elastic APM endpoint (_without_ `https://` prefix) that _must_ also include the port (example: `1234567.apm.us-west2.gcp.elastic-cloud.com:443`).
   - `Bearer YOUR_APM_SECRET_TOKEN`: your Elastic APM secret token. Note that in this branch you MUST place either `Bearer` or `ApiKey` in front of the token. On ESS / self-managed you will generally use `Bearer`, on serverless you will generally use `ApiKey`.
3. Execute the following commands to deploy the OpenTelemetry demo to your Kubernetes cluster:

   ```
   # clone this repository
   git clone https://github.com/elastic/opentelemetry-demo

   # switch to the kubernetes/elastic-helm directory
   cd kubernetes/elastic-helm

   # !(when running it for the first time) add the open-telemetry Helm repostiroy
   helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts

   # !(when an older helm open-telemetry repo exists) update the open-telemetry helm repo
   helm repo update open-telemetry

   # deploy the demo through helm install
   helm install -f deployment.yaml my-otel-demo open-telemetry/opentelemetry-demo
   ```

4. Update your `hosts` file to redirect `otel-demo.internal` to `127.0.0.1`.

#### Kubernetes monitoring

This demo already enables cluster level metrics collection with `clusterMetrics` and
Kubernetes events collection with `kubernetesEvents`.

In order to add Node level metrics collection we can run an additional Otel collector Daemonset with the following:

1. Create a secret in Kubernetes with the following command.

   ```
   kubectl create secret generic elastic-secret-ds \
     --from-literal=elastic_endpoint='YOUR_ELASTICSEARCH_ENDPOINT' \
     --from-literal=elastic_api_key='YOUR_ELASTICSEARCH_API_KEY'
   ```

   Don't forget to replace

   - `YOUR_ELASTICSEARCH_ENDPOINT`: your Elasticsearch endpoint (_with_ `https://` prefix example: `https://1234567.us-west2.gcp.elastic-cloud.com:443`).
   - `YOUR_ELASTICSEARCH_API_KEY`: your Elasticsearch API Key

2. Execute the following command to deploy the OpenTelemetry Collector to your Kubernetes cluster, in the same directory `kubernetes/elastic-helm` in this repository.

```
# deploy the Elastic OpenTelemetry collector distribution through helm install
helm install otel-daemonset open-telemetry/opentelemetry-collector --values daemonset.yaml
```

## Explore and analyze the data With Elastic

### Service map

![Service map](service-map.png "Service map")

### Traces

![Traces](trace.png "Traces")

### Correlation

![Correlation](correlation.png "Correlation")

### Logs

![Logs](logs.png "Logs")
