<!-- markdownlint-disable-next-line -->
# <img src="https://opentelemetry.io/img/logos/opentelemetry-logo-nav.png" alt="OTel logo" width="32"> :heavy_plus_sign: <img src="https://images.contentstack.io/v3/assets/bltefdd0b53724fa2ce/blt601c406b0b5af740/620577381692951393fdf8d6/elastic-logo-cluster.svg" alt="OTel logo" width="32"> OpenTelemetry Demo with Elastic Observability

The following guide describes how to setup the OpenTelemetry demo with Elastic Observability using [Docker compose](#docker-compose) or [Kubernetes](#kubernetes). This fork introduces several changes to the agents used in the demo:

- The Java agent within the [Ad](../src/adservice/Dockerfile.elastic), the [Fraud Detection](../src/frauddetectionservice/Dockerfile.elastic) and the [Kafka](../src/kafka/Dockerfile.elastic) services have been replaced with the Elastic distribution of the OpenTelemetry Java Agent. You can find more information about the Elastic distribution in [this blog post](https://www.elastic.co/observability-labs/blog/elastic-distribution-opentelemetry-java-agent).
- The .NET agent within the [Cart service](../src/cartservice/src/Directory.Build.props) has been replaced with the Elastic distribution of the OpenTelemetry .NET Agent. You can find more information about the Elastic distribution in [this blog post](https://www.elastic.co/observability-labs/blog/elastic-opentelemetry-distribution-dotnet-applications).
- The Elastic distribution of the OpenTelemetry Node.js Agent has replaced the OpenTelemetry Node.js agent in the [Payment service](../src/paymentservice/package.json). Additional details about the Elastic distribution are available in [this blog post](https://www.elastic.co/observability-labs/blog/elastic-opentelemetry-distribution-node-js).
- The Elastic distribution for OpenTelemetry Python has replaced the OpenTelemetry Python agent in the [Recommendation service](..src/recommendationservice/requirements.txt). Additional details about the Elastic distribution are available in [this blog post](https://www.elastic.co/observability-labs/blog/elastic-opentelemetry-distribution-python).

Additionally, the OpenTelemetry Contrib collector has also been changed to the [Elastic OpenTelemetry Collector distribution](https://github.com/elastic/elastic-agent/blob/main/internal/pkg/otel/README.md). This ensures a more integrated and optimized experience with Elastic Observability.

## Docker compose

1. Start a free trial on [Elastic Cloud](https://cloud.elastic.co/) and copy the `endpoint` and `secretToken` from the Elastic APM setup instructions in your Kibana.
1. Open the file `src/otelcollector/otelcol-elastic-config-extras.yaml` in an editor and replace the following two placeholders:
   - `YOUR_APM_ENDPOINT_WITHOUT_HTTPS_PREFIX`: your Elastic APM endpoint (*without* `https://` prefix) that *must* also include the port (example: `1234567.apm.us-west2.gcp.elastic-cloud.com:443`).
   - `YOUR_APM_SECRET_TOKEN`: your Elastic APM secret token.
1. Start the demo with the following command from the repository's root directory:
   ```
   make start
   ```

## Kubernetes
### Prerequisites:
- Create a Kubernetes cluster. There are no specific requirements, so you can create a local one, or use a managed Kubernetes cluster, such as [GKE](https://cloud.google.com/kubernetes-engine), [EKS](https://aws.amazon.com/eks/), or [AKS](https://azure.microsoft.com/en-us/products/kubernetes-service).
- Set up [kubectl](https://kubernetes.io/docs/reference/kubectl/).
- Set up [Helm](https://helm.sh/).

### Start the Demo
1. Setup Elastic Observability on Elastic Cloud.
1. Create a secret in Kubernetes with the following command.
   ```
   kubectl create secret generic elastic-secret \
     --from-literal=elastic_apm_endpoint='YOUR_APM_ENDPOINT_WITHOUT_HTTPS_PREFIX' \
     --from-literal=elastic_apm_secret_token='YOUR_APM_SECRET_TOKEN'
   ```
   Don't forget to replace
   - `YOUR_APM_ENDPOINT_WITHOUT_HTTPS_PREFIX`: your Elastic APM endpoint (*without* `https://` prefix) that *must* also include the port (example: `1234567.apm.us-west2.gcp.elastic-cloud.com:443`).
   - `YOUR_APM_SECRET_TOKEN`: your Elastic APM secret token, include the Bearer or ApiKey but not the "Authorization=" part e.g. Bearer XXXXXX or ApiKey XXXXX below is an example:
   ```
   kubectl create secret generic elastic-secret \
     --from-literal=elastic_apm_endpoint='12345.apm.us-west2.gcp.elastic-cloud.com:443' \
     --from-literal=elastic_apm_secret_token='Bearer 123456789123456YE2'
   ```
1. Execute the following commands to deploy the OpenTelemetry demo to your Kubernetes cluster:
   ```
   # clone this repository
   git clone https://github.com/elastic/opentelemetry-demo
   
   # switch to the kubernetes/elastic-helm directory
   cd opentelemetry-demo/kubernetes/elastic-helm

   # !(when running it for the first time) add the open-telemetry Helm repostiroy
   helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts

   # !(when an older helm open-telemetry repo exists) update the open-telemetry helm repo
   helm repo update open-telemetry

   # deploy the demo through helm install
   helm install -f deployment.yaml my-otel-demo open-telemetry/opentelemetry-demo
   ```

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
   - `YOUR_ELASTICSEARCH_ENDPOINT`: your Elasticsearch endpoint (*with* `https://` prefix example: `https://1234567.us-west2.gcp.elastic-cloud.com:443`).
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

## Testing with a custom component

Suppose you want to see how your new processor is going to play out in this demo app. You can create a custom OpenTelemetry collector and test it within this demo app by following these steps:
1. Follow the instructions in the [elastic-collector-componenets](https://github.com/elastic/opentelemetry-collector-components/blob/main/README.md) repo in order to build a Docker image
   that contains your custom component
2. Edit the [deployment.yaml](https://github.com/elastic/opentelemetry-demo/blob/main/kubernetes/elastic-helm/deployment.yaml) file:
   - change the `opentelemetry-collector` [image definitions](https://github.com/elastic/opentelemetry-demo/blob/27b4923ba9acd316d3726a29aad1f7e32299bc8c/kubernetes/elastic-helm/deployment.yaml#L36)
   to point at your custom image repository and tag
   - add your component configuration to the proper sub-section of the [`config` section](https://github.com/elastic/opentelemetry-demo/blob/27b4923ba9acd316d3726a29aad1f7e32299bc8c/kubernetes/elastic-helm/deployment.yaml#L62). For example, if you are testing a processor, make sure to add its config to the `processors` sub-section.
   - add your component to the proper sub-section of the [`service` section](https://github.com/elastic/opentelemetry-demo/blob/27b4923ba9acd316d3726a29aad1f7e32299bc8c/kubernetes/elastic-helm/deployment.yaml#L96). For example, if you are testing a logs processor, make sure to add its config to the `processors` sub-section of the `logs` pipeline.
3. If you wish to enable Kubernetes node level metrics collection, edit the [daemonset.yaml](https://github.com/elastic/opentelemetry-demo/blob/main/kubernetes/elastic-helm/daemonset.yaml) file:
   - change the [`image` section](https://github.com/elastic/opentelemetry-demo/blob/27b4923ba9acd316d3726a29aad1f7e32299bc8c/kubernetes/elastic-helm/deployment.yaml#L36)
   to point at your custom image repository and tag
   - add your component configuration to the proper sub-section of the [`config` section](https://github.com/elastic/opentelemetry-demo/blob/27b4923ba9acd316d3726a29aad1f7e32299bc8c/kubernetes/elastic-helm/daemonset.yaml#L57). For example, if you are testing a processor, make sure to add its config to the `processors` sub-section.
   - add your component to the proper sub-section of the [`service` section](https://github.com/elastic/opentelemetry-demo/blob/27b4923ba9acd316d3726a29aad1f7e32299bc8c/kubernetes/elastic-helm/daemonset.yaml#L309). For example, if you are testing a logs processor, make sure to add its config to the `processors` sub-section of the `logs` pipeline.
4. Apply the Helm chart changes and install it:
   ```
   # !(when running it for the first time) add the open-telemetry Helm repostiroy
   helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts

   # !(when an older helm open-telemetry repo exists) update the open-telemetry helm repo
   helm repo update open-telemetry

   # deploy the demo through helm install
   helm install -f deployment.yaml my-otel-demo open-telemetry/opentelemetry-demo
   ```
