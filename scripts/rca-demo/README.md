# RCA KubeCon Demo Scripts

Docs for running scripts in this folder. 

### Prerequisites

On a mac you can easily install these prerequisites with: `brew install minikube helm kubernetes-cli`

- Create a Kubernetes cluster. For local development `minikube` is recommended. There are no specific requirements, so you can create a local one, or use a managed Kubernetes cluster, such as [GKE](https://cloud.google.com/kubernetes-engine), [EKS](https://aws.amazon.com/eks/), or [AKS](https://azure.microsoft.com/en-us/products/kubernetes-service).
- Set up [kubectl](https://kubernetes.io/docs/reference/kubectl/).
- Set up [Helm](https://helm.sh/).
- Install the Nginx Ingress Controller:
- Set up [Minikube](https://minikube.sigs.k8s.io/docs/)

```
helm install --namespace kube-system nginx ingress-nginx --repo https://kubernetes.github.io/ingress-nginx
```

## setup

The fast way to set things up is with the `setup` script. Before running it, be sure to copy 
[the .env.example file](./.env.example) and add all of the required values. Each script file SHOULD
source this .env file for you, but if it doesn't, run `$ source scripts/rca-demo/.env` to make sure.

Run the setup script from the repo root:

```
./scripts/rca-demo/setup
```

The output will guide you if you are missing anything required to make this work. You can check the
status of the pods by running `kubectl get pods`. 

Assuming everything is now running correctly, you should be able to visit the Astronomy Shop in
your browser at http://otel-demo.internal, and see signals in your configured ES/Kibana.

## trigger-demo scenario

The `trigger-demo-scenario` script will cause the cart service to fail to start properly. You can use this to test how the solution responds to the problem.

For the full scenario, set up a custom threshold rule like this:

![Custom threshold rule](threshold_rule.png "Custom threshold rule")

This rule will trigger when the demo scenario is activated and will be associated with the nginx ingress controller service. It can be used as a starting point to showcase the different exploration capabilities of the stack.

With `trigger-demo-scenario restore`, the system can be put back into a working state again.
