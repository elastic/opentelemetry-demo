#!/usr/bin/env python3
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0

import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[2] / ".github/scripts/prepare_upstream_merge.py"


class UpstreamMergeTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="upstream-merge-test-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.git("init", "-b", "main")
        self.git("config", "user.name", "Upstream Merge Test")
        self.git("config", "user.email", "test@example.invalid")
        (self.repo / "shared.txt").write_text("original\n", encoding="utf-8")
        self.git("add", ".")
        self.git("commit", "-m", "Base")

    def git(self, *args):
        return subprocess.run(
            ["git", *args], cwd=self.repo, check=True, capture_output=True, text=True
        ).stdout.strip()

    def commit_file(self, name, content, message):
        (self.repo / name).write_text(content, encoding="utf-8")
        self.git("add", name)
        self.git("commit", "-m", message)

    def prepare(self, upstream_ref="upstream", base_ref="main"):
        output = self.root / "output.txt"
        summary = self.root / "summary.md"
        environment = os.environ.copy()
        environment["GITHUB_OUTPUT"] = str(output)
        environment["GITHUB_STEP_SUMMARY"] = str(summary)
        subprocess.run(
            [sys.executable, str(SCRIPT), "--upstream-ref", upstream_ref,
             "--base-ref", base_ref,
             "--run-id", "123", "--run-attempt", "1",
             "--output-dir", str(self.root / "artifacts")],
            cwd=self.repo, env=environment, check=True, capture_output=True, text=True,
        )
        return dict(line.split("=", 1) for line in output.read_text().splitlines()), summary.read_text()

    def test_clean_merge_contains_upstream_changes(self):
        self.git("switch", "-c", "upstream")
        self.commit_file("upstream.txt", "upstream\n", "Upstream change")
        upstream_sha = self.git("rev-parse", "HEAD")
        self.git("switch", "main")
        self.commit_file("fork.txt", "fork\n", "Fork change")

        output, summary = self.prepare()

        self.assertEqual(output["has_changes"], "true")
        self.assertEqual(output["has_conflicts"], "false")
        self.assertEqual(output["branch_name"], "auto-merge/upstream-123-1")
        self.assertEqual(len(self.git("rev-list", "--parents", "-n", "1", "HEAD").split()), 3)
        self.git("merge-base", "--is-ancestor", upstream_sha, "HEAD")
        self.assertEqual((self.repo / "upstream.txt").read_text(), "upstream\n")
        self.assertIn(upstream_sha, Path(output["body_file"]).read_text())
        self.assertIn("Proposed branch:", summary)

    def test_conflict_creates_draft_pr_report(self):
        self.git("switch", "-c", "upstream")
        self.commit_file("shared.txt", "upstream\n", "Upstream change")
        upstream_sha = self.git("rev-parse", "HEAD")
        self.git("switch", "main")
        self.commit_file("shared.txt", "fork\n", "Fork change")

        output, summary = self.prepare()

        self.assertEqual(output["has_changes"], "true")
        self.assertEqual(output["has_conflicts"], "true")
        self.assertIn("shared.txt", output["conflict_summary"])
        self.assertEqual(len(self.git("rev-list", "--parents", "-n", "1", "HEAD").split()), 2)
        report = (self.repo / ".github/upstream-sync/merge-conflicts.md").read_text()
        body = Path(output["body_file"]).read_text()
        self.assertIn(upstream_sha, report)
        self.assertIn("shared.txt", body)
        self.assertIn("git merge --no-ff", body)
        self.assertIn("shared.txt", summary)
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_no_new_upstream_commits_creates_nothing(self):
        head = self.git("rev-parse", "HEAD")

        output, summary = self.prepare("main")

        self.assertEqual(output["has_changes"], "false")
        self.assertEqual(self.git("rev-parse", "HEAD"), head)
        self.assertEqual(self.git("branch", "--show-current"), "main")
        self.assertIn("No new upstream commits", summary)

    def test_branch_dry_run_uses_main_as_merge_base(self):
        self.git("switch", "-c", "upstream")
        self.commit_file("upstream.txt", "upstream\n", "Upstream change")
        self.git("switch", "main")
        base_sha = self.git("rev-parse", "HEAD")
        self.git("branch", "origin/main", base_sha)
        self.git("switch", "-c", "workflow-review")
        self.commit_file("workflow.txt", "review\n", "Workflow change")

        output, _ = self.prepare(base_ref="origin/main")

        self.assertEqual(output["has_changes"], "true")
        self.assertEqual(self.git("rev-parse", "HEAD^1"), base_sha)
        self.assertFalse((self.repo / "workflow.txt").exists())


if __name__ == "__main__":
    unittest.main()
