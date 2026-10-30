---
name: elastic-upstream-sync
description: Merge upstream OpenTelemetry Demo changes into the Elastic fork, resolve sync PR conflicts, and update Elastic overrides or patches affected by upstream changes.
---

# Elastic upstream sync

Read `.github/ELASTIC_MAINTENANCE.md` from the repository root before changing
the sync branch. Follow `AGENTS.md`, including its restriction on posting
agent-written issue or PR text.

Check the worktree and identify the fork's main and OpenTelemetry upstream main
refs before merging. They are `main`, `origin/main`, and `upstream/main` in some
local clones, but remote names and local branches can differ. Inspect the
remotes and refs, then fetch the needed upstream commit. Preserve unrelated
local edits and credentials. The sync workflow's conflict branch contains a
report, not a partial upstream merge:
read `.github/upstream-sync/merge-conflicts.md`, fetch the recorded commit,
rerun the merge, resolve conflicts, and remove the report.

Favor current upstream behavior in shared files. Retain only required Elastic
differences, preferably in fork-owned Compose layers, `Dockerfile.elastic`
files, Helm overrides, or the Cart/Accounting patches. Inspect the final tree
against upstream as well as the commits introduced by the sync branch. Treat a
clean merge as unverified until the rendered Docker modes, builds, and
telemetry pass the relevant checks in the maintenance guide.

Do not post a generated PR description or comment. If posting is requested,
the exact text must first be supplied by the human or approved verbatim by
them immediately before posting, as required by `AGENTS.md`.
