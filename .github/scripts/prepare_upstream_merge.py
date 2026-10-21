#!/usr/bin/env python3
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0

import argparse
import os
import re
import subprocess
from pathlib import Path


UPSTREAM_URL = "https://github.com/open-telemetry/opentelemetry-demo.git"
REPORT_PATH = Path(".github/upstream-sync/merge-conflicts.md")


def git(*args, check=True):
    result = subprocess.run(["git", *args], capture_output=True, text=True)
    if check and result.returncode:
        raise RuntimeError(f"git {' '.join(args)} failed:\n{result.stderr}")
    return result


def write_output(**values):
    if output_path := os.environ.get("GITHUB_OUTPUT"):
        with open(output_path, "a", encoding="utf-8") as output:
            for key, value in values.items():
                output.write(f"{key}={value}\n")


def write_summary(content):
    if summary_path := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(summary_path, "a", encoding="utf-8") as summary:
            summary.write(content)


def code(value):
    return f"`{value.replace('`', '``')}`"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-ref", default="main")
    parser.add_argument("--upstream-ref", default="upstream/main")
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--run-attempt", required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()

    if not re.fullmatch(r"[0-9]+", args.run_id) or not re.fullmatch(r"[0-9]+", args.run_attempt):
        parser.error("run ID and attempt must be numeric")
    if git("status", "--porcelain").stdout.strip():
        raise RuntimeError("The checkout must be clean before merging upstream")

    upstream_sha = git("rev-parse", args.upstream_ref).stdout.strip()
    commits_behind = int(git("rev-list", "--count", f"{args.base_ref}..{upstream_sha}").stdout)
    if commits_behind == 0:
        write_output(has_changes="false", has_conflicts="false")
        write_summary(f"## Upstream sync\n\nNo new upstream commits at {code(upstream_sha)}.\n")
        print("No new upstream commits")
        return

    branch = f"auto-merge/upstream-{args.run_id}-{args.run_attempt}"
    git("switch", "-c", branch, args.base_ref)
    merge = git("merge", "--no-ff", "--no-edit", upstream_sha, check=False)
    conflicts = []
    if merge.returncode:
        result = subprocess.run(
            ["git", "diff", "--name-only", "--diff-filter=U", "-z"],
            capture_output=True,
            check=True,
        )
        conflicts = [os.fsdecode(path) for path in result.stdout.split(b"\0") if path]
        if not conflicts:
            raise RuntimeError(f"Merge failed without file conflicts:\n{merge.stderr}")
        git("merge", "--abort")
        REPORT_PATH.parent.mkdir(parents=True, exist_ok=True)
        REPORT_PATH.write_text(
            "# Upstream merge conflicts\n\n"
            f"Upstream commit: {code(upstream_sha)}\n\n"
            "The upstream merge stopped on these files:\n\n"
            + "".join(f"- {code(path)}\n" for path in conflicts)
            + "\nRe-run the merge locally, resolve the conflicts, and remove this report.\n",
            encoding="utf-8",
        )
        git("add", "--", str(REPORT_PATH))
        git("commit", "-m", f"Record conflicts merging upstream {upstream_sha[:12]}")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    body_file = args.output_dir / "upstream-merge-pr-body.md"
    if conflicts:
        body = (
            "## Upstream sync needs conflict resolution\n\n"
            f"This branch records an attempted merge of {code(upstream_sha)} "
            f"({commits_behind} new upstream commits). The upstream changes have not been merged yet.\n\n"
            "Conflicting files:\n\n"
            + "".join(f"- {code(path)}\n" for path in conflicts)
            + f"\nCheck out {code(branch)}, then:\n\n"
            "```sh\n"
            f"git fetch {UPSTREAM_URL} main\n"
            f"git merge --no-ff {upstream_sha}\n"
            "# Resolve the conflicts and remove .github/upstream-sync/merge-conflicts.md.\n"
            "git add -A\n"
            "git commit\n"
            "git push\n"
            "```\n\n"
            "Run the relevant checks before marking this draft PR ready for review.\n"
        )
        title = "chore: Sync upstream OpenTelemetry Demo (conflicts)"
    else:
        body = (
            "## Upstream sync\n\n"
            f"Merge {commits_behind} commits from {code(UPSTREAM_URL)} "
            f"through {code(upstream_sha)} into `main`.\n\n"
            "Review the merged changes and run the relevant checks before merging this PR.\n"
        )
        title = "chore: Sync upstream OpenTelemetry Demo"
    body_file.write_text(body, encoding="utf-8")

    conflict_summary = ", ".join(path.replace("\n", " ").replace("\r", " ") for path in conflicts)
    write_output(
        has_changes="true",
        has_conflicts=str(bool(conflicts)).lower(),
        branch_name=branch,
        upstream_sha=upstream_sha,
        body_file=body_file,
        title=title,
        conflict_summary=conflict_summary[:1000],
    )
    write_summary(f"## Upstream sync\n\nProposed branch: {code(branch)}\n\n{body}")
    print(f"Prepared {branch}: {'conflicts' if conflicts else 'clean merge'}")


if __name__ == "__main__":
    main()
