# Elastic integration tests

Run these tests from the repository root before pushing changes to the Elastic
demo. They build images from your current checkout and verify that Docker and
Kubernetes deployments send recent traces to a local Elasticsearch instance.
No Elastic Cloud credentials are needed.

## Prerequisites

- Docker with Docker Compose, `curl`, and Python 3. Docker must have enough
  resources to run the full demo and a local Elasticsearch instance.
- For Kubernetes tests, also install `kind`, `kubectl`, and Helm.
- Keep the demo's local ports available. Stop any existing demo deployment
  before running the tests.
- Use a checkout without an `elastic-start-local/` directory. The runner
  refuses to replace an existing start-local installation.

The first run downloads images and builds all demo services, so it can take
several minutes.

## Run locally

```sh
./test/elastic/run_local.sh          # Docker and Kubernetes
./test/elastic/run_local.sh docker   # Docker only
./test/elastic/run_local.sh k8s      # Kubernetes only
```

The Docker run also builds upstream images and checks that Cart and Accounting
emit the expected upstream and Elastic telemetry. Both deployment modes then
start a temporary local Elastic stack, make checkout requests, and check
Elasticsearch for recent traces from the expected services and Elastic distro
attributes on EDOT-instrumented services.

The Kubernetes run creates a Kind cluster named `chart-testing` if one does
not exist, loads the images built from your checkout, and verifies those images
are selected by the demo pods. It uses a temporary kubeconfig, so your active
Kubernetes context is unchanged. If `chart-testing` already exists, the runner
reuses it but refuses to replace an existing demo or Elastic collector Helm
release.

The tests tear down the demo and temporary Elastic stack even on failure, and
restore `.env.override` after each deployment. A Kind cluster is deleted only
if the runner created it. Locally built Docker images remain available for
subsequent runs. On failure, the runner prints service status and relevant
logs to help diagnose the problem.

CI runs the same checks in
[Elastic Integration Tests](../../.github/workflows/run-integration-tests-elastic.yml).
