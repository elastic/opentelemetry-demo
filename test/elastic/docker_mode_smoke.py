#!/usr/bin/env python3
# Copyright The OpenTelemetry Authors
# SPDX-License-Identifier: Apache-2.0

import json
import os
import platform
import subprocess
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BASE_FILES = ["compose.yaml", "compose.full.yaml", "compose.extras.yaml"]
ELASTIC_FILES = [
    "compose.yaml",
    "compose.full.yaml",
    "compose.extras.yaml",
    "docker-compose.elastic.yml",
]
UPSTREAM_FILES = BASE_FILES + ["docker-compose.upstream.yml"]


def command(args, *, input_bytes=None, timeout=120):
    result = subprocess.run(
        args,
        cwd=ROOT,
        input=input_bytes,
        capture_output=True,
        timeout=timeout,
    )
    if result.returncode:
        raise RuntimeError(
            f"{' '.join(args)} failed:\n{result.stdout.decode(errors='replace')}"
            f"{result.stderr.decode(errors='replace')}"
        )
    return result.stdout.decode(errors="replace").strip()


def compose_config(mode):
    files = ELASTIC_FILES if mode == "elastic" else UPSTREAM_FILES
    args = ["docker", "compose", "--env-file", ".env"]
    if mode == "elastic":
        args += ["--env-file", ".env.override"]
    for file in files:
        args += ["-f", file]
    args += ["config", "--format", "json"]
    environment = os.environ.copy()
    environment["ELASTIC_OTLP_ENDPOINT"] = "https://example.invalid"
    environment["ELASTIC_OTLP_API_KEY"] = "smoke-test-placeholder"
    image_variable = "INTEGRATION_TEST_IMAGE_NAME" if mode == "elastic" else "UPSTREAM_TEST_IMAGE_NAME"
    if image_variable in environment:
        environment["IMAGE_NAME"] = environment[image_variable]
    if "INTEGRATION_TEST_DEMO_VERSION" in environment:
        environment["DEMO_VERSION"] = environment["INTEGRATION_TEST_DEMO_VERSION"]
    result = subprocess.run(args, cwd=ROOT, env=environment, capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError(f"Compose config failed: {result.stderr}")
    return json.loads(result.stdout)["services"]


def validate_modes(upstream, elastic):
    unexpected = {"grafana", "jaeger", "opensearch", "prometheus", "opamp-server"} & elastic.keys()
    if unexpected:
        raise AssertionError(f"Elastic mode includes upstream observability services: {unexpected}")
    for service, config in upstream.items():
        if "build" in config and not config["build"]["dockerfile"].endswith("/Dockerfile"):
            raise AssertionError(f"Upstream mode selects a nonstandard Dockerfile for {service}")
    elastic_dockerfiles = {
        "accounting": "./src/accounting/Dockerfile.elastic",
        "ad": "./src/ad/Dockerfile.elastic",
        "cart": "./src/cart/src/Dockerfile.elastic",
        "fraud-detection": "./src/fraud-detection/Dockerfile.elastic",
        "kafka": "./src/kafka/Dockerfile.elastic",
        "payment": "./src/payment/Dockerfile.elastic",
        "quote": "./src/quote/Dockerfile.elastic",
    }
    for service, dockerfile in elastic_dockerfiles.items():
        if elastic[service]["build"]["dockerfile"] != dockerfile:
            raise AssertionError(f"Elastic mode selects the wrong Dockerfile for {service}")
    if "opentelemetry-collector-contrib" not in upstream["otel-collector"]["image"]:
        raise AssertionError("Upstream mode does not select Collector Contrib")
    if "elastic-agent" not in elastic["otel-collector"]["image"]:
        raise AssertionError("Elastic mode does not select Elastic Agent")
    if elastic["otel-collector"]["environment"].get("ELASTIC_AGENT_OTEL") != "true":
        raise AssertionError("Elastic Agent is not configured to run in OTel mode")
    for mode, services, expected in (
        ("upstream", upstream, "otelcol-config-extras-elastic.yml"),
        ("elastic", elastic, "otelcol-elastic-config.yaml"),
    ):
        mounts = [volume["source"] for volume in services["otel-collector"]["volumes"]]
        if not any(path.endswith(expected) for path in mounts):
            raise AssertionError(f"{mode} mode does not mount {expected}")


def varint(data, offset):
    value = 0
    shift = 0
    while True:
        byte = data[offset]
        offset += 1
        value |= (byte & 127) << shift
        if byte < 128:
            return value, offset
        shift += 7


def fields(data):
    offset = 0
    while offset < len(data):
        tag, offset = varint(data, offset)
        number, wire_type = tag >> 3, tag & 7
        if wire_type == 0:
            value, offset = varint(data, offset)
        elif wire_type in (1, 5):
            size = 8 if wire_type == 1 else 4
            value, offset = data[offset : offset + size], offset + size
        elif wire_type == 2:
            size, offset = varint(data, offset)
            value, offset = data[offset : offset + size], offset + size
        else:
            raise ValueError(f"Unsupported protobuf wire type {wire_type}")
        yield number, value


def first(data, number, default=b""):
    return next((value for field, value in fields(data) if field == number), default)


def attributes(resource):
    result = {}
    for number, key_value in fields(resource):
        if number == 1:
            key = first(key_value, 1).decode()
            result[key] = first(first(key_value, 2), 1).decode(errors="replace")
    return result


def trace_spans(payload):
    for number, resource_spans in fields(payload):
        if number != 1:
            continue
        resource = attributes(first(resource_spans, 1))
        for scope_field, scope_spans in fields(resource_spans):
            if scope_field != 2:
                continue
            for span_field, span in fields(scope_spans):
                if span_field == 2:
                    yield resource, first(span, 5).decode(), first(span, 6, 0)


class Receiver(ThreadingHTTPServer):
    def __init__(self):
        self.records = []
        self.lock = threading.Lock()
        super().__init__(("0.0.0.0", 0), self.handler())

    def handler(self):
        receiver = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                body = self.rfile.read(int(self.headers["Content-Length"]))
                with receiver.lock:
                    receiver.records.append((self.path, body))
                self.send_response(200)
                self.end_headers()

            def log_message(self, *_):
                pass

        return Handler

    def spans(self):
        with self.lock:
            records = list(self.records)
        return [span for path, body in records if path == "/v1/traces" for span in trace_spans(body)]

    def clear(self):
        with self.lock:
            self.records.clear()


def wait_for(predicate, description, timeout=60):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if predicate():
            return
        time.sleep(0.5)
    raise AssertionError(f"Timed out waiting for {description}")


def docker_run(name, network, image, environment, extra=()):
    args = ["docker", "run", "-d", "--name", name, "--network", network]
    if platform.system() == "Linux":
        args += ["--add-host", "host.docker.internal:host-gateway"]
    for key, value in environment.items():
        args += ["-e", f"{key}={value}"]
    command(args + list(extra) + [image])


def stop_container(name):
    subprocess.run(["docker", "rm", "-f", name], cwd=ROOT, capture_output=True)


def check_distro(spans, name, expected):
    matching = [(resource, kind) for resource, span_name, kind in spans if span_name == name]
    if len(matching) != 1:
        raise AssertionError(f"Expected one {name!r} span, found {len(matching)}")
    distro = matching[0][0].get("telemetry.distro.name")
    if expected == "elastic" and distro != "elastic":
        raise AssertionError(f"Expected EDOT span, got telemetry.distro.name={distro!r}")
    if expected == "upstream" and distro == "elastic":
        raise AssertionError("Upstream mode emitted an EDOT span")


def main():
    upstream = compose_config("upstream")
    elastic = compose_config("elastic")
    validate_modes(upstream, elastic)
    suffix = uuid.uuid4().hex[:8]
    network = f"otel-mode-smoke-{suffix}"
    receiver = Receiver()
    thread = threading.Thread(target=receiver.serve_forever, daemon=True)
    thread.start()
    created = []
    network_created = False
    try:
        for services in (upstream, elastic):
            for service in ("cart", "accounting"):
                command(["docker", "image", "inspect", services[service]["image"]])
        command(["docker", "image", "inspect", upstream["kafka"]["image"]])
        command(["docker", "network", "create", network])
        network_created = True
        broker = f"{network}-kafka"
        valkey = f"{network}-valkey"
        docker_run(
            broker,
            network,
            upstream["kafka"]["image"],
            {
                "KAFKA_ADVERTISED_LISTENERS": "PLAINTEXT://kafka:9092",
                "KAFKA_LISTENERS": "PLAINTEXT://kafka:9092,CONTROLLER://kafka:9093",
                "KAFKA_CONTROLLER_QUORUM_VOTERS": "1@kafka:9093",
                "KAFKA_HEAP_OPTS": "-Xmx400m -Xms400m",
                "KAFKA_OPTS": "",
                "JAVA_TOOL_OPTIONS": "",
            },
            ("--network-alias", "kafka"),
        )
        created.append(broker)
        docker_run(valkey, network, upstream["valkey-cart"]["image"], {}, ("--network-alias", "valkey"))
        created.append(valkey)
        wait_for(
            lambda: subprocess.run(
                ["docker", "exec", valkey, "valkey-cli", "ping"], capture_output=True
            ).stdout.strip() == b"PONG",
            "Valkey",
        )
        wait_for(
            lambda: subprocess.run(
                ["docker", "exec", "-e", "KAFKA_OPTS=", "-e", "JAVA_TOOL_OPTIONS=", broker,
                 "/opt/kafka/bin/kafka-topics.sh", "--bootstrap-server", "kafka:9092", "--list"],
                capture_output=True,
            ).returncode == 0,
            "Kafka",
            timeout=120,
        )

        for mode, services in (("upstream", upstream), ("elastic", elastic)):
            receiver.clear()
            cart = f"{network}-{mode}-cart"
            docker_run(
                cart,
                network,
                services["cart"]["image"],
                {
                    "VALKEY_ADDR": "valkey:6379",
                    "FLAGD_HOST": "flagd",
                    "ASPNETCORE_HTTP_PORTS": "7070",
                    "OTEL_EXPORTER_OTLP_ENDPOINT": f"http://host.docker.internal:{receiver.server_port}",
                    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
                    "OTEL_BSP_SCHEDULE_DELAY": "200",
                },
                ("-p", "127.0.0.1::7070"),
            )
            created.append(cart)
            wait_for(lambda: "Now listening on" in command(["docker", "logs", cart]), f"{mode} Cart")
            port = command(["docker", "port", cart, "7070/tcp"]).rsplit(":", 1)[1]
            response = command(
                ["curl", "--http2-prior-knowledge", "--silent", "--show-error", "--output", "/dev/null",
                 "--write-out", "%{http_code}", f"http://127.0.0.1:{port}/"]
            )
            if response != "200":
                raise AssertionError(f"{mode} Cart returned HTTP {response}")
            wait_for(
                lambda: any(name == "GET /" for _, name, _ in receiver.spans()),
                f"{mode} Cart server span",
            )
            check_distro(receiver.spans(), "GET /", mode)
            stop_container(cart)
            created.remove(cart)
            print(f"{mode} Cart: one server span")

            receiver.clear()
            topic = f"orders-{mode}-{suffix}"
            command(
                ["docker", "exec", "-e", "KAFKA_OPTS=", "-e", "JAVA_TOOL_OPTIONS=", broker,
                 "/opt/kafka/bin/kafka-topics.sh", "--bootstrap-server", "kafka:9092", "--create",
                 "--topic", topic, "--partitions", "1", "--replication-factor", "1"]
            )
            accounting = f"{network}-{mode}-accounting"
            docker_run(
                accounting,
                network,
                services["accounting"]["image"],
                {
                    "KAFKA_ADDR": "kafka:9092",
                    "KAFKA_TOPIC": topic,
                    "OTEL_SERVICE_NAME": f"accounting-{mode}-smoke",
                    "OTEL_EXPORTER_OTLP_ENDPOINT": f"http://host.docker.internal:{receiver.server_port}",
                    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
                    "OTEL_BSP_SCHEDULE_DELAY": "200",
                },
            )
            created.append(accounting)
            wait_for(lambda: "Application started" in command(["docker", "logs", accounting]), f"{mode} Accounting")
            command(
                ["docker", "exec", "-i", "-e", "KAFKA_OPTS=", "-e", "JAVA_TOOL_OPTIONS=", broker,
                 "/opt/kafka/bin/kafka-console-producer.sh", "--bootstrap-server", "kafka:9092",
                 "--topic", topic],
                input_bytes=b"\x12\x04test\n",
            )
            wait_for(
                lambda: any(name == "order-consumed" for _, name, _ in receiver.spans()),
                f"{mode} Accounting consumer span",
            )
            check_distro(receiver.spans(), "order-consumed", mode)
            stop_container(accounting)
            created.remove(accounting)
            print(f"{mode} Accounting: one consumer span")
    finally:
        for container in reversed(created):
            stop_container(container)
        if network_created:
            subprocess.run(["docker", "network", "rm", network], cwd=ROOT, capture_output=True)
        receiver.shutdown()
        receiver.server_close()


if __name__ == "__main__":
    main()
