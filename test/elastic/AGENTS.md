# Elastic integration tests

The repository-root `AGENTS.md` also applies. Read [the local test guide](README.md)
and [Elastic maintenance guide](../../.github/ELASTIC_MAINTENANCE.md) when changing
these tests.

- Test observable behavior: successful deployment alone does not prove telemetry
  reached Elasticsearch. Keep assertions for recent service traces and Elastic
  distro attributes on EDOT-instrumented services.
- Preserve the distinction between `./demo.sh docker` and
  `./demo.sh docker upstream`. The Docker mode smoke test must catch accidental
  Elastic Dockerfile selection in upstream mode and verify Cart and Accounting
  instrumentation in both modes.
- In Kubernetes tests, verify that pods use images built from the checkout, not
  only that Helm releases and pods become ready.
- Preserve the local runner's cleanup of temporary resources and restoration
  of the user's `.env.override`. Run the relevant command from `README.md` when
  changing test behavior.
