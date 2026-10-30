# Elastic Helm overrides

The repository-root `AGENTS.md` also applies. Read
[the Elastic maintenance guide](../../.github/ELASTIC_MAINTENANCE.md) when
changing these values.

- `demo.yml` and `kube-stack-overrides.yml` are used by `./demo.sh k8s`;
  `demo-upstream.yml` is used by `./demo.sh k8s upstream`. Keep the two
  deployment paths distinct.
- When upstream changes the demo chart, compare the chart version selected by
  `demo.sh` with its templates and defaults. Keep only fork-required overrides,
  including service endpoints, environment variables, and image selection.
- Keep Elastic credentials in Kubernetes Secrets and reference them from values
  files; do not add credential values to these files.
- Validate changes with the Kubernetes integration test in
  `test/elastic/README.md`. Check that pods select images built from the current
  checkout and that recent telemetry reaches Elasticsearch.
