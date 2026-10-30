# Maintaining the Elastic fork

This guide covers the decisions that matter when merging
`open-telemetry/opentelemetry-demo` into this fork. Start with the current
[sync workflow](workflows/merge-upstream.yaml),
[merge helper](scripts/prepare_upstream_merge.py), and
[Elastic test instructions](../test/elastic/README.md); they are the source of
truth when commands or file names change.

## Understand the sync branch

The scheduled workflow fetches upstream `main` and creates a branch from
`origin/main`. A clean merge produces a normal PR. On conflict, the helper
aborts the attempted merge and commits only
`.github/upstream-sync/merge-conflicts.md` on the new branch. That draft PR
does **not** contain the upstream changes yet. Check out the PR branch, fetch
the exact upstream commit recorded in the report, rerun the merge, resolve it,
remove the report, and push the branch. Review the resulting merge commit and
the PR diff before making the draft ready for review. The workflow's dry run
prepares the branch and PR text without pushing, opening a PR, or notifying
Slack.

Use the upstream side as the starting point for shared files. Reapply only the
Elastic behavior required for this fork, ideally in fork-owned files such as
`Dockerfile.elastic`, `docker-compose.elastic.yml`, and
`kubernetes/elastic-helm/`. A clean text merge can still change build inputs,
Compose interpolation, chart behavior, or emitted telemetry. Avoid copying old
upstream files back into the branch merely to preserve a previous override.

Before reviewing a sync, identify the fork's main and OpenTelemetry upstream
main refs. The examples below assume local `main`, `origin/main`, and
`upstream/main` refs; check `git remote -v` and `git show-ref` first. A fresh
checkout may have no `upstream` remote or local `main` branch. Fetch the
upstream commit recorded by the workflow, and substitute the actual refs or
commit IDs where needed. Then distinguish two comparisons:

```sh
git diff --name-status main...HEAD          # Changes introduced on the sync branch
git diff --name-status upstream/main HEAD  # Current tree against upstream's tree
git diff --check main...HEAD
```

The second command includes intentional Elastic fork differences; inspect
those paths rather than expecting an empty diff. A
local `main` may lag `origin/main`, so check the refs before interpreting the
first command. Keep local credentials out of the review: `.env.override` may
contain an API key. Do not print or stage it when preparing a sync.

## Keep both Docker modes working

`./demo.sh docker` combines the base Compose files with
`docker-compose.elastic.yml` and selects the Elastic Agent and per-service
`Dockerfile.elastic` overrides. `./demo.sh docker upstream` instead applies
`docker-compose.upstream.yml`, selecting upstream Dockerfiles and the upstream
Collector. The upstream Collector may still export to Elastic when credentials
are configured; that does not make its instrumentation EDOT. Avoid relying on
`.env.override` to choose Dockerfiles for upstream mode: it is used by the
Elastic Docker mode and can contain local credentials.

Keep service-specific Elastic instrumentation in Elastic Dockerfiles or other
fork-owned files where possible. Cart and Accounting apply
`src/cart/elastic/zero-code.patch` and `src/accounting/elastic/edot.patch`
during their Elastic image builds. When upstream changes their source, inspect
the new upstream code and adjust the patches to that code. Verify that the
upstream images still build and emit upstream telemetry, and that the Elastic
images emit `telemetry.distro.name: elastic`. The
[Docker mode smoke test](../test/elastic/docker_mode_smoke.py) checks rendered
Compose choices and exercises Cart and Accounting in both modes.

## Check deployment and telemetry

Run the cheap rendered-Compose check first:

```sh
python3 test/elastic/docker_mode_smoke.py --config-only
python3 -m unittest discover -s test/elastic -p test_merge_upstream.py
```

Then run the relevant local integration tests as documented in
[`test/elastic/README.md`](../test/elastic/README.md):

```sh
./test/elastic/run_local.sh docker
./test/elastic/run_local.sh k8s
```

These tests build from the checkout, verify Docker mode behavior, and check
recent service traces in a local Elasticsearch instance. Kubernetes testing
loads the checkout's images into Kind and confirms that the demo pods select
them. The pinned demo Helm chart can differ from current upstream application
settings, so review `kubernetes/elastic-helm/demo.yml` when chart defaults,
ports, or environment variables change. When a test fails, distinguish image
build failure, deployment failure, and missing telemetry; container health alone
does not prove that Elastic received data.
