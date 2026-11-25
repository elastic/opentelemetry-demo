#!/usr/bin/env python3
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0

import argparse
import base64
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path
from urllib.parse import urlencode


PATCHES = ("src/cart/elastic/zero-code.patch", "src/accounting/elastic/edot.patch")
REPAIR_MARKER = "Upstream-Patch-Repair:"
WORKFLOW = "repair-upstream-dotnet-patches.yml"
MAX_PATCH_BYTES = 256 * 1024


def api(path, method="GET", data=None):
    args = ["gh", "api", "--method", method, path]
    if data is not None:
        args += ["--input", "-"]
    result = subprocess.run(args, input=json.dumps(data) if data is not None else None,
                            capture_output=True, text=True, check=True, timeout=120)
    return json.loads(result.stdout)


def pages(path, key=None):
    separator = "&" if "?" in path else "?"
    for page in range(1, 101):
        result = api(f"{path}{separator}per_page=100&page={page}")
        items = result[key] if key else result
        yield from items
        if len(items) < 100:
            return
    raise RuntimeError("API pagination limit reached; refusing an incomplete check")


def output(**values):
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as stream:
        for key, value in values.items():
            stream.write(f"{key}={value}\n")


def eligible_pr(run, pr, repo):
    # Match only branches created by prepare_upstream_merge.py, including its numeric run ID and attempt.
    branch = re.fullmatch(r"auto-merge/upstream-([0-9]+)-([0-9]+)", pr["head"]["ref"])
    return bool(
        branch and pr["state"] == "open" and not pr["draft"]
        and pr["base"]["ref"] == "main" and pr["base"]["repo"]["full_name"] == repo
        and pr["head"].get("repo") and pr["head"]["repo"]["full_name"] == repo
        and pr["head"]["sha"] == run["head_sha"]
        and pr["head"]["ref"] == run["head_branch"]
        and pr["title"] == "chore: Sync upstream OpenTelemetry Demo"
    )


def inspect(context):
    output(eligible="false")
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    repo = os.environ["GITHUB_REPOSITORY"]
    root = f"repos/{repo}"
    run = api(f"{root}/actions/runs/{int(event['workflow_run']['id'])}")
    if (run["conclusion"] != "failure" or run["event"] != "pull_request"
            or run["path"] != ".github/workflows/run-integration-tests-elastic.yml"
            or run["head_repository"]["full_name"] != repo
            or int(os.environ["GITHUB_RUN_ATTEMPT"]) != 1):
        print("Not an eligible integration failure")
        return
    query = urlencode({"state": "open", "base": "main", "head": f"{repo.split('/')[0]}:{run['head_branch']}"})
    prs = [pr for pr in pages(f"{root}/pulls?{query}") if eligible_pr(run, pr, repo)]
    if len(prs) != 1:
        print("No unique current, same-repository upstream-sync PR")
        return
    pr = prs[0]
    _, sync_id, attempt = pr["head"]["ref"].rsplit("-", 2)
    sync = api(f"{root}/actions/runs/{int(sync_id)}")
    if (sync["path"] != ".github/workflows/merge-upstream.yaml" or sync["conclusion"] != "success"
            or sync["event"] not in ("schedule", "workflow_dispatch") or int(sync["run_attempt"]) < int(attempt)):
        print("Could not verify the source merge workflow")
        return
    commits = pages(f"{root}/pulls/{pr['number']}/commits")
    if any(REPAIR_MARKER in commit["commit"]["message"] for commit in commits):
        print("This PR already received an automatic patch repair")
        return
    current_id = int(os.environ["GITHUB_RUN_ID"])
    previous = pages(f"{root}/actions/workflows/{WORKFLOW}/runs?event=workflow_run", "workflow_runs")
    title = f"Repair .NET patches: {run['head_sha']}"
    if any(item["display_title"] == title and int(item["id"]) < current_id for item in previous):
        print("An automatic attempt already exists for this PR head")
        return
    jobs = pages(f"{root}/actions/runs/{run['id']}/attempts/{run['run_attempt']}/jobs", "jobs")
    if not any(step["name"] == "Build images from source" and step["conclusion"] == "failure"
               for job in jobs for step in job.get("steps", [])):
        print("The failure was not in the Elastic image build")
        return
    context.mkdir(parents=True, exist_ok=True)
    log = subprocess.run(
        ["gh", "run", "view", str(run["id"]), "--repo", repo, "--attempt", str(run["run_attempt"]), "--log-failed"],
        capture_output=True, text=True, check=True, timeout=120,
    ).stdout
    (context / "failure.log").write_text(log[-512 * 1024:], encoding="utf-8")
    output(eligible="true", pr_number=pr["number"], head_sha=pr["head"]["sha"], branch=pr["head"]["ref"])


def git(checkout, *args, check=True):
    return subprocess.run(["git", "-C", str(checkout), *args], capture_output=True, text=True,
                          check=check, timeout=120)


def probe(checkout):
    if (checkout / ".github/upstream-sync/merge-conflicts.md").exists():
        raise RuntimeError("The upstream merge still needs conflict resolution")
    failed = []
    for patch in PATCHES:
        result = git(checkout, "apply", "--check", patch, check=False)
        if result.returncode:
            failed.append(patch)
    return failed


def candidate_files(candidate):
    expected = {str(Path(patch).relative_to("src")) for patch in PATCHES}
    actual = set()
    for path in candidate.rglob("*"):
        if path.is_symlink():
            raise RuntimeError("Candidate contains a symlink")
        if path.is_file():
            actual.add(str(path.relative_to(candidate)))
    if actual != expected:
        raise RuntimeError("Candidate must contain exactly the two allowed patch files")
    files = {}
    for patch in PATCHES:
        path = candidate / Path(patch).relative_to("src")
        if not 0 < path.stat().st_size <= MAX_PATCH_BYTES:
            raise RuntimeError("Invalid candidate patch size")
        files[patch] = path.read_bytes()
    return files


def digest(files):
    return hashlib.sha256(b"".join(path.encode() + b"\0" + files[path] + b"\0" for path in PATCHES)).hexdigest()


def apply_candidate(checkout, candidate):
    files = candidate_files(candidate)
    for patch, content in files.items():
        destination = checkout / patch
        if destination.is_symlink() or not destination.is_file():
            raise RuntimeError("Patch target must be an existing regular file")
        destination.write_bytes(content)
    git(checkout, "diff", "--check")
    changed = git(checkout, "diff", "--name-only").stdout.splitlines()
    if not changed:
        print("No repair proposed")
        return None
    if not set(changed) <= set(PATCHES):
        raise RuntimeError("Changes outside the patch allowlist")
    if probe(checkout):
        raise RuntimeError("Candidate patches do not apply")
    return digest(files)


def publish(candidate, pr_number, expected_sha, expected_digest):
    repo = os.environ["GITHUB_REPOSITORY"]
    root = f"repos/{repo}"
    files = candidate_files(candidate)
    if digest(files) != expected_digest:
        raise RuntimeError("Candidate differs from the validated artifact")
    pr = api(f"{root}/pulls/{pr_number}")
    run = {"head_sha": expected_sha, "head_branch": pr["head"]["ref"]}
    if not eligible_pr(run, pr, repo):
        raise RuntimeError("PR closed, changed head, or is no longer an eligible sync")
    if any(REPAIR_MARKER in item["commit"]["message"] for item in pages(f"{root}/pulls/{pr_number}/commits")):
        raise RuntimeError("This PR already received an automatic patch repair")
    parent = api(f"{root}/git/commits/{expected_sha}")
    tree = []
    for path, content in files.items():
        blob = api(f"{root}/git/blobs", "POST", {"content": base64.b64encode(content).decode(), "encoding": "base64"})
        tree.append({"path": path, "mode": "100644", "type": "blob", "sha": blob["sha"]})
    result = api(f"{root}/git/trees", "POST", {"base_tree": parent["tree"]["sha"], "tree": tree})
    if result["sha"] == parent["tree"]["sha"]:
        raise RuntimeError("Refusing an empty repair commit")
    commit = api(f"{root}/git/commits", "POST", {
        "message": f"fix: refresh Elastic .NET patches after upstream sync\n\n{REPAIR_MARKER} {pr_number}\nAssisted-by: GitHub Copilot\n",
        "tree": result["sha"], "parents": [expected_sha],
    })
    latest = api(f"{root}/pulls/{pr_number}")
    if not eligible_pr(run, latest, repo):
        raise RuntimeError("PR changed during publication; nothing pushed")
    api(f"{root}/git/refs/heads/{pr['head']['ref']}", "PATCH", {"sha": commit["sha"], "force": False})
    print(f"Published patch repair commit {commit['sha']}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("inspect", "probe", "apply", "publish"))
    parser.add_argument("--checkout", type=Path)
    parser.add_argument("--candidate", type=Path)
    parser.add_argument("--context", type=Path)
    parser.add_argument("--pr", type=int)
    parser.add_argument("--sha")
    parser.add_argument("--digest")
    args = parser.parse_args()
    if args.mode == "inspect":
        inspect(args.context)
    elif args.mode == "probe":
        failed = probe(args.checkout)
        output(needs_repair=str(bool(failed)).lower())
        print("Stale patches: " + (", ".join(failed) or "none"))
    elif args.mode == "apply":
        value = apply_candidate(args.checkout, args.candidate)
        output(changed=str(value is not None).lower(), digest=value or "")
    else:
        publish(args.candidate, args.pr, args.sha, args.digest)


if __name__ == "__main__":
    main()
