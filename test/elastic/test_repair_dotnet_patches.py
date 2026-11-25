# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0

import copy
import importlib.util
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[2] / ".github/scripts/repair_dotnet_patches.py"
SPEC = importlib.util.spec_from_file_location("repair_dotnet_patches", SCRIPT)
repair = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(repair)


def pull_request():
    return {
        "number": 42, "state": "open", "draft": False,
        "title": "chore: Sync upstream OpenTelemetry Demo",
        "base": {"ref": "main", "repo": {"full_name": "elastic/demo"}},
        "head": {"ref": "auto-merge/upstream-100-1", "sha": "a" * 40, "repo": {"full_name": "elastic/demo"}},
    }


class PatchRepairTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.checkout = self.root / "checkout"
        self.checkout.mkdir()
        self.candidate = self.root / "candidate"
        self.candidate.mkdir()
        self.git("init", "-q")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.invalid")
        for patch_path in repair.PATCHES:
            service = patch_path.split("/")[1]
            source = self.checkout / "src" / service / "Program.cs"
            source.parent.mkdir(parents=True)
            source.write_text("upstream\n")
            original = self.patch(service, "old")
            destination = self.checkout / patch_path
            destination.parent.mkdir(parents=True)
            destination.write_text(original)
            candidate = self.candidate / Path(patch_path).relative_to("src")
            candidate.parent.mkdir(parents=True)
            candidate.write_text(self.patch(service, "upstream"))
        self.git("add", ".")
        self.git("commit", "-qm", "fixture")

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.checkout), *args], check=True,
                              capture_output=True, text=True).stdout

    @staticmethod
    def patch(service, old):
        return (f"diff --git a/src/{service}/Program.cs b/src/{service}/Program.cs\n"
                f"--- a/src/{service}/Program.cs\n+++ b/src/{service}/Program.cs\n"
                f"@@ -1 +1 @@\n-{old}\n+elastic\n")

    def test_real_patch_failure_and_repair(self):
        self.assertEqual(set(repair.probe(self.checkout)), set(repair.PATCHES))
        value = repair.apply_candidate(self.checkout, self.candidate)
        self.assertEqual(len(value), 64)
        self.assertEqual(repair.probe(self.checkout), [])
        self.assertEqual(self.git("show", "HEAD:src/cart/Program.cs"), "upstream\n")
        self.assertEqual((self.checkout / "src/cart/Program.cs").read_text(), "upstream\n")

    def test_unchanged_candidate_is_noop(self):
        for patch_path in repair.PATCHES:
            (self.candidate / Path(patch_path).relative_to("src")).write_bytes((self.checkout / patch_path).read_bytes())
        self.assertIsNone(repair.apply_candidate(self.checkout, self.candidate))

    def test_still_broken_candidate_rejected(self):
        (self.candidate / "cart/elastic/zero-code.patch").write_text(self.patch("cart", "wrong"))
        with self.assertRaisesRegex(RuntimeError, "do not apply"):
            repair.apply_candidate(self.checkout, self.candidate)

    def test_extra_file_and_symlink_rejected(self):
        extra = self.candidate / "Dockerfile"
        extra.write_text("unexpected")
        with self.assertRaisesRegex(RuntimeError, "exactly"):
            repair.candidate_files(self.candidate)
        extra.unlink()
        extra.symlink_to(self.checkout / "src/cart/Program.cs")
        with self.assertRaisesRegex(RuntimeError, "symlink"):
            repair.candidate_files(self.candidate)

    def test_conflict_report_rejected(self):
        report = self.checkout / ".github/upstream-sync/merge-conflicts.md"
        report.parent.mkdir(parents=True)
        report.write_text("unresolved")
        with self.assertRaisesRegex(RuntimeError, "conflict resolution"):
            repair.probe(self.checkout)

    def test_foreign_draft_stale_and_non_sync_prs_rejected(self):
        run = {"head_sha": "a" * 40, "head_branch": "auto-merge/upstream-100-1"}
        original = pull_request()
        self.assertTrue(repair.eligible_pr(run, original, "elastic/demo"))
        for keys, value in (
            (("head", "repo", "full_name"), "someone/fork"),
            (("head", "sha"), "b" * 40), (("head", "ref"), "feature"),
            (("draft",), True), (("state",), "closed"), (("base", "ref"), "release"),
        ):
            pr = copy.deepcopy(original)
            target = pr
            for key in keys[:-1]:
                target = target[key]
            target[keys[-1]] = value
            with self.subTest(keys=keys):
                self.assertFalse(repair.eligible_pr(run, pr, "elastic/demo"))

    def test_publisher_only_writes_patch_blobs_and_nonforce_ref(self):
        calls = []
        pr = pull_request()

        def api(path, method="GET", data=None):
            calls.append((path, method, data))
            if "/pulls/42" in path:
                return pr
            if path.endswith("/git/commits/" + "a" * 40):
                return {"tree": {"sha": "old-tree"}}
            return {"sha": "new-object"}

        with patch.dict(os.environ, {"GITHUB_REPOSITORY": "elastic/demo"}), \
                patch.object(repair, "api", side_effect=api), patch.object(repair, "pages", return_value=iter([])):
            repair.publish(self.candidate, 42, "a" * 40, repair.digest(repair.candidate_files(self.candidate)))
        tree = next(data for path, method, data in calls if path.endswith("/git/trees"))
        self.assertEqual({item["path"] for item in tree["tree"]}, set(repair.PATCHES))
        self.assertEqual(calls[-1][1:], ("PATCH", {"sha": "new-object", "force": False}))
        commit = next(data for path, method, data in calls if path.endswith("/git/commits") and method == "POST")
        self.assertIn("Assisted-by: GitHub Copilot", commit["message"])
        self.assertEqual(commit["parents"], ["a" * 40])

    def test_publisher_rejects_changed_head_and_artifact(self):
        value = repair.digest(repair.candidate_files(self.candidate))
        pr = pull_request()
        pr["head"]["sha"] = "b" * 40
        with patch.dict(os.environ, {"GITHUB_REPOSITORY": "elastic/demo"}), patch.object(repair, "api", return_value=pr) as api:
            with self.assertRaisesRegex(RuntimeError, "changed head"):
                repair.publish(self.candidate, 42, "a" * 40, value)
            self.assertEqual(api.call_count, 1)
            api.reset_mock()
            with self.assertRaisesRegex(RuntimeError, "validated artifact"):
                repair.publish(self.candidate, 42, "a" * 40, "incorrect")
            api.assert_not_called()

    def test_inspection_skips_repeated_attempt_without_invoking_agent(self):
        run = {
            "id": 200, "head_sha": "a" * 40, "head_branch": "auto-merge/upstream-100-1",
            "conclusion": "failure", "event": "pull_request", "run_attempt": 1,
            "path": ".github/workflows/run-integration-tests-elastic.yml",
            "head_repository": {"full_name": "elastic/demo"},
        }
        event = self.root / "event.json"
        event.write_text(json.dumps({"workflow_run": {"id": 200}}))
        outputs = self.root / "outputs"
        env = {"GITHUB_EVENT_PATH": str(event), "GITHUB_REPOSITORY": "elastic/demo", "GITHUB_RUN_ID": "300",
               "GITHUB_RUN_ATTEMPT": "1", "GITHUB_OUTPUT": str(outputs)}

        def api(path, *args):
            if path.endswith("/200"):
                return run
            return {"path": ".github/workflows/merge-upstream.yaml", "event": "schedule", "run_attempt": 1, "conclusion": "success"}

        def pages(path, key=None):
            if key == "workflow_runs":
                return iter([{"id": 250, "display_title": "Repair .NET patches: " + "a" * 40}])
            if path.endswith("/commits"):
                return iter([])
            return iter([pull_request()])

        with patch.dict(os.environ, env), patch.object(repair, "api", side_effect=api), \
                patch.object(repair, "pages", side_effect=pages):
            repair.inspect(self.root / "context")
        self.assertEqual(outputs.read_text(), "eligible=false\n")
        self.assertFalse((self.root / "context").exists())

    def test_inspection_accepts_only_verified_elastic_build_failures(self):
        run = {
            "id": 200, "head_sha": "a" * 40, "head_branch": "auto-merge/upstream-100-1",
            "conclusion": "failure", "event": "pull_request", "run_attempt": 1,
            "path": ".github/workflows/run-integration-tests-elastic.yml",
            "head_repository": {"full_name": "elastic/demo"},
        }
        sync = {"path": ".github/workflows/merge-upstream.yaml", "event": "schedule",
                "run_attempt": 1, "conclusion": "success"}
        event = self.root / "event.json"
        event.write_text(json.dumps({"workflow_run": {"id": 200}}))
        outputs = self.root / "outputs"
        env = {"GITHUB_EVENT_PATH": str(event), "GITHUB_REPOSITORY": "elastic/demo", "GITHUB_RUN_ID": "300",
               "GITHUB_RUN_ATTEMPT": "1", "GITHUB_OUTPUT": str(outputs)}
        for scenario in ("accepted", "wrong_step", "spoofed_sync", "already_repaired", "foreign_run"):
            with self.subTest(scenario=scenario):
                outputs.write_text("")
                source = copy.deepcopy(run)
                origin = copy.deepcopy(sync)
                if scenario == "foreign_run":
                    source["head_repository"]["full_name"] = "someone/fork"
                if scenario == "spoofed_sync":
                    origin["path"] = ".github/workflows/other.yml"

                def api(path, *args):
                    return source if path.endswith("/200") else origin

                def pages(path, key=None):
                    if key == "workflow_runs":
                        return iter([])
                    if key == "jobs":
                        step = "Build images from source" if scenario == "accepted" else "Test Docker Elastic telemetry"
                        return iter([{"steps": [{"name": step, "conclusion": "failure"}]}])
                    if path.endswith("/commits"):
                        message = repair.REPAIR_MARKER if scenario == "already_repaired" else "upstream merge"
                        return iter([{"commit": {"message": message}}])
                    return iter([pull_request()])

                with patch.dict(os.environ, env), patch.object(repair, "api", side_effect=api), \
                        patch.object(repair, "pages", side_effect=pages), \
                        patch.object(repair.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "diagnostic log")) as logs:
                    repair.inspect(self.root / "context")
                if scenario == "accepted":
                    self.assertIn("eligible=true\npr_number=42\nhead_sha=" + "a" * 40, outputs.read_text())
                    self.assertEqual((self.root / "context/failure.log").read_text(), "diagnostic log")
                    logs.assert_called_once()
                else:
                    self.assertEqual(outputs.read_text(), "eligible=false\n")
                    logs.assert_not_called()

    def test_pr_moving_during_publication_never_updates_ref(self):
        pr = pull_request()
        calls = []
        reads = 0

        def api(path, method="GET", data=None):
            nonlocal reads
            calls.append((path, method))
            if "/pulls/42" in path:
                reads += 1
                result = copy.deepcopy(pr)
                if reads > 1:
                    result["head"]["sha"] = "b" * 40
                return result
            if path.endswith("/git/commits/" + "a" * 40):
                return {"tree": {"sha": "old-tree"}}
            return {"sha": "new-object"}

        with patch.dict(os.environ, {"GITHUB_REPOSITORY": "elastic/demo"}), \
                patch.object(repair, "api", side_effect=api), patch.object(repair, "pages", return_value=iter([])):
            with self.assertRaisesRegex(RuntimeError, "changed during publication"):
                repair.publish(self.candidate, 42, "a" * 40, repair.digest(repair.candidate_files(self.candidate)))
        self.assertFalse(any(method == "PATCH" for _, method in calls))


if __name__ == "__main__":
    unittest.main()
