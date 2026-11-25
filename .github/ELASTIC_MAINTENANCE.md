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

## Automatic .NET patch repair

[`Repair upstream .NET patches`](workflows/repair-upstream-dotnet-patches.yml)
listens for completed `Elastic Integration Tests` runs. It only handles failures
in `Build images from source` on an open, non-draft, same-repository upstream-sync
PR targeting `main`. The branch must have been created by a successful run of
`merge-upstream.yaml`, and the failed run must match the PR's current head.
Conflict-report branches are excluded. Both patches are checked against the
source before invoking an agent; if they still apply, the failure needs manual
investigation.

The Copilot agent proposes edits to `src/cart/elastic/zero-code.patch` and
`src/accounting/elastic/edot.patch` as an artifact. Separate jobs check the file
allowlist, apply both patches, build Cart and Accounting in upstream and Elastic
modes, and run `docker_mode_smoke.py` to verify .NET telemetry. A successful
validation publishes a patch-only commit to the existing PR branch using the
GitHub API. The publisher verifies the artifact digest and PR head again, never
force-updates a branch, and does not execute PR code or use agent-generated Git
history. The App-authenticated commit triggers the normal integration checks.
The agent cannot post issues, PR descriptions, or comments, and no PR is merged
automatically.

Enable this only in the repository that runs the upstream merge workflow:

1. Merge both the controller YAML and the generated agent lock file into the
   default branch. `workflow_run` does not activate from a feature branch.
2. Configure `COPILOT_GITHUB_TOKEN` for a Copilot account permitted to use the
   repository's agentic workflows. Only this secret is forwarded to the agent;
   its repository token has read access. See
   [Copilot authentication](https://github.github.com/gh-aw/reference/engines/copilot/).
3. Verify that `token-policy-e96fbab0a32e`, reused from the merge workflow,
   permits the new controller's `publish` job to mint a repository-scoped App
   token with contents write and pull requests read access. The policy may
   already permit it; otherwise its administrator must update it. The App must
   be installed in this repository. Publishing fails if authorization is absent.
4. Set the repository Actions variable `UPSTREAM_PATCH_REPAIR_ENABLED` to `true`.
   Remove it or set it to `false` to stop new automatic repairs.

There is at most one automatic attempt per PR head SHA, including failed or
cancelled attempts, and at most one published repair per upstream-sync PR. A
workflow rerun is skipped. After a failed attempt, investigate manually or push
a human correction to create a new head SHA. After a published repair, any
remaining failures require manual investigation. The attempt guard reads the
repository's Actions run history; deleting that history also removes that guard.
Diagnostics and proposed patches remain in workflow artifacts for seven days.

The agent source is [`repair-dotnet-patches.md`](workflows/repair-dotnet-patches.md).
Regenerate its lock file with the pinned compiler and action release:

```sh
gh extension install github/gh-aw --pin v1.2.2
gh aw compile repair-dotnet-patches --no-check-update --action-mode action \
  --action-tag 5c7541d098b1fd0b039865a2e69849b0fe3c679c
python3 -m unittest discover -s test/elastic -p 'test_*.py'
```
