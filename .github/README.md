<!-- markdownlint-disable-next-line -->
# <img src="https://opentelemetry.io/img/logos/opentelemetry-logo-nav.png" alt="OTel logo" width="32"> :heavy_plus_sign: <img src="https://images.contentstack.io/v3/assets/bltefdd0b53724fa2ce/blt601c406b0b5af740/620577381692951393fdf8d6/elastic-logo-cluster.svg" alt="OTel logo" width="32"> OpenTelemetry Demo with Elastic Observability

## Testathon APM (Kubernetes)

### Prerequisites:
- Create a Kubernetes cluster. There are no specific requirements, so you can create a local one, or use a managed Kubernetes cluster, such as [GKE](https://cloud.google.com/kubernetes-engine), [EKS](https://aws.amazon.com/eks/), or [AKS](https://azure.microsoft.com/en-us/products/kubernetes-service).
- Set up [kubectl](https://kubernetes.io/docs/reference/kubectl/).
- Set up [Helm](https://helm.sh/).

### Start the Demo
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

   # Create a configmap for flagd errors configuration
   kubectl apply -f flagd-errors.yaml


   # deploy the demo through helm install
   helm install -f deployment.yaml my-otel-demo open-telemetry/opentelemetry-demo

   # Create the required secrets; replace CHANGE_ME_FOR_THE_ELASTICSEARCH_PASSWORD
   kubectl create secret generic elastic-secret-testathon --from-literal=elastic_password='CHANGE_ME_FOR_THE_ELASTICSEARCH_PASSWORD'

   # deploy the daemonset collector through helm install
   helm install otel-daemonset open-telemetry/opentelemetry-collector --values daemonset.yaml
   ```
2. Generate some traffic:
   ```
   # Locate a Pod named "my-otel-demo-frontendproxy-<RANDOM_SUFFIX>"
   kubectl get pods

   # Forward the fronend proxy port
   k port-forward my-otel-demo-frontendproxy-<RANDOM_SUFFIX_CHANGE_ME> 8080:8080

   # Visit localhost:8080 in your browser
   ```
