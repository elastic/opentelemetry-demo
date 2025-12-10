#!/usr/bin/env bash

set -e -o pipefail

source "${CURRENT_DIR}/test/elastic/utils.sh"

function set_up_before_script() {
  start_local_elastic_stack
}

function tear_down_after_script() {
  uninstall_local_elastic_stack
}

function test_launch_demo_k8s() {
  echo "=== DEBUG: Starting K8s test ==="
  echo "About to call launch_demo with cloud-hosted k8s"
  launch_demo "cloud-hosted" "k8s"
  echo "=== DEBUG: K8s test completed ==="
}

function test_destroy_demo_k8s() {
  destroy_demo "k8s"
}
