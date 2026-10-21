#!/usr/bin/env python3

import importlib.util
import json
import os
import sys
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("demo_services", ROOT / "test/telemetry/services.py")
SERVICES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SERVICES)

PRODUCT_ID = "0PUK6V6EV0"
EDOT_SERVICES = {"accounting", "ad", "cart", "fraud-detection", "payment", "quote"}
EXPECTED_SERVICES = set(SERVICES.services_with_signal("traces", "full")) - {
    "frontend-web", "image-provider"
}
PERSON = {
    "email": "elastic-integration-test@example.com",
    "address": {
        "streetAddress": "1600 Amphitheatre Parkway",
        "zipCode": "94043",
        "city": "Mountain View",
        "state": "CA",
        "country": "United States",
    },
    "userCurrency": "USD",
    "creditCard": {
        "creditCardNumber": "4432-8015-6152-0454",
        "creditCardExpirationMonth": 1,
        "creditCardExpirationYear": 2039,
        "creditCardCvv": 672,
    },
}


def request_json(url, *, payload=None, api_key=None, timeout=10, parse_json=True):
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"ApiKey {api_key}"
    body = json.dumps(payload).encode() if payload is not None else None
    request = urllib.request.Request(url, data=body, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            data = response.read()
    except urllib.error.HTTPError as error:
        detail = error.read(300).decode(errors="replace").replace("\n", " ")
        raise OSError(f"{url} returned HTTP {error.code}: {detail}") from error
    return json.loads(data) if data and parse_json else None


def drive_checkout(frontend_url):
    user_id = str(uuid.uuid4())
    request_json(f"{frontend_url}/api/products/{PRODUCT_ID}", parse_json=False)
    request_json(f"{frontend_url}/api/recommendations?productIds={PRODUCT_ID}", parse_json=False)
    request_json(f"{frontend_url}/api/data/?contextKeys=binoculars", parse_json=False)
    request_json(
        f"{frontend_url}/api/cart",
        payload={"item": {"productId": PRODUCT_ID, "quantity": 1}, "userId": user_id},
        parse_json=False,
    )
    request_json(
        f"{frontend_url}/api/checkout", payload={**PERSON, "userId": user_id},
        timeout=20, parse_json=False,
    )


def resource_attribute(document, name):
    resource = document.get("resource", {})
    attributes = resource.get("attributes", {}) if isinstance(resource, dict) else {}
    if name in attributes:
        return attributes[name]
    current = attributes
    for part in name.split("."):
        if not isinstance(current, dict):
            return None
        current = current.get(part)
    return current


def spans_for_service(es_url, api_key, service, since):
    query = {
        "size": 10,
        "sort": [{"@timestamp": {"order": "desc"}}],
        "query": {
            "bool": {
                "filter": [
                    {"term": {"service.name": service}},
                    {"range": {"@timestamp": {"gte": since}}},
                ]
            }
        },
    }
    result = request_json(f"{es_url.rstrip('/')}/traces-*/_search", payload=query, api_key=api_key)
    return [hit.get("_source", {}) for hit in result.get("hits", {}).get("hits", [])]


def verify(es_url, api_key, frontend_url, timeout=300):
    since = datetime.now(timezone.utc).isoformat()
    deadline = time.monotonic() + timeout
    probe_deadline = min(time.monotonic() + 120, deadline - 60)
    last_probe_error = None
    successful_probes = 0
    attempts = 0
    while successful_probes < 5 and time.monotonic() < probe_deadline:
        attempts += 1
        try:
            drive_checkout(frontend_url)
            successful_probes += 1
            print(f"Checkout probe {successful_probes}/5 succeeded", flush=True)
        except (OSError, ValueError) as error:
            last_probe_error = str(error)
            print(f"Checkout probe attempt {attempts} failed: {error}", flush=True)
        time.sleep(2)

    if successful_probes == 0:
        raise AssertionError(f"No checkout probe succeeded; last error: {last_probe_error}")

    missing = set(EXPECTED_SERVICES)
    missing_edot = set(EDOT_SERVICES)
    last_query_error = None
    while time.monotonic() < deadline:
        for service in sorted(missing | missing_edot):
            try:
                spans = spans_for_service(es_url, api_key, service, since)
            except (OSError, ValueError) as error:
                last_query_error = str(error)
                continue
            if spans:
                missing.discard(service)
            if any(resource_attribute(span, "telemetry.distro.name") == "elastic" for span in spans):
                missing_edot.discard(service)
        if not missing and not missing_edot:
            print(f"Elasticsearch contains traces from all {len(EXPECTED_SERVICES)} expected services")
            return
        time.sleep(5)

    raise AssertionError(
        f"Timed out waiting for Elasticsearch telemetry. Missing traces: {sorted(missing)}; "
        f"missing EDOT distro: {sorted(missing_edot)}; "
        f"last Elasticsearch error: {last_query_error}; last checkout error: {last_probe_error}"
    )


if __name__ == "__main__":
    try:
        verify(
            os.environ["ES_LOCAL_URL"],
            os.environ["ES_LOCAL_API_KEY"],
            os.environ.get("ELASTIC_TEST_FRONTEND_URL", "http://localhost:8080"),
            int(os.environ.get("ELASTIC_TEST_TIMEOUT", "300")),
        )
    except (AssertionError, KeyError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
