#!/usr/bin/env python3

import sys
import unittest
from pathlib import Path
from unittest.mock import patch


sys.path.insert(0, str(Path(__file__).resolve().parent))
import verify_telemetry as telemetry


class VerifyTelemetryTests(unittest.TestCase):
    def test_resource_attribute_reads_otel_native_document(self):
        document = {"resource": {"attributes": {"telemetry.distro.name": "elastic"}}}
        self.assertEqual(telemetry.resource_attribute(document, "telemetry.distro.name"), "elastic")

    def test_missing_export_reports_services(self):
        with (
            patch.object(telemetry, "drive_checkout"),
            patch.object(telemetry, "spans_for_service", return_value=[]),
            patch.object(telemetry.time, "sleep"),
            patch.object(telemetry.time, "monotonic", side_effect=[0] * 8 + [301]),
        ):
            with self.assertRaisesRegex(AssertionError, "Missing traces:.*checkout"):
                telemetry.verify("http://localhost:9200", "test-key", "http://localhost:8080")

    def test_missing_elastic_distro_reports_services(self):
        with (
            patch.object(telemetry, "drive_checkout"),
            patch.object(telemetry, "spans_for_service", return_value=[{"resource": {"attributes": {}}}]),
            patch.object(telemetry.time, "sleep"),
            patch.object(telemetry.time, "monotonic", side_effect=[0] * 8 + [301]),
        ):
            with self.assertRaisesRegex(AssertionError, "missing EDOT distro:.*payment"):
                telemetry.verify("http://localhost:9200", "test-key", "http://localhost:8080")


if __name__ == "__main__":
    unittest.main()
