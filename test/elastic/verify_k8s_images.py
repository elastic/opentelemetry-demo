#!/usr/bin/env python3

import importlib.util
import json
import os
import subprocess
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("demo_services", ROOT / "test/telemetry/services.py")
SERVICES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SERVICES)

repository = os.environ["DEMO_HELM_IMAGE_REPOSITORY"]
tag = os.environ["DEMO_HELM_IMAGE_TAG"]
expected = set(SERVICES.ALL_SERVICES) - {"frontend-web"}
expected.add("kafka")

deadline = time.monotonic() + 60
while True:
    output = subprocess.check_output(["kubectl", "get", "pods", "-o", "json"], text=True)
    pods = json.loads(output)["items"]
    seen = set()
    wrong = {}
    for pod in pods:
        service = pod["metadata"].get("labels", {}).get("app.kubernetes.io/component")
        if service not in expected:
            continue
        seen.add(service)
        images = [container["image"] for container in pod["spec"]["containers"]]
        wanted = f"{repository}:{tag}-{service}"
        if wanted not in images:
            wrong[pod["metadata"]["name"]] = images
    missing = sorted(expected - seen)
    if not missing or time.monotonic() >= deadline:
        break
    time.sleep(2)

if missing or wrong:
    raise AssertionError(f"Kubernetes pods do not select PR-built demo images: missing={missing}, wrong={wrong}")

print(f"Kubernetes pods select PR-built images for {len(expected)} demo services")
