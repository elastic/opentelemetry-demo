#!/usr/bin/env bash

set -e -o pipefail

source "${CURRENT_DIR}/test/elastic/utils.sh"

function set_up_before_script() {
  start_local_elastic_stack
}

function tear_down_after_script() {
  uninstall_local_elastic_stack
}

function assert_demo_launched() {
  local deployment_type="$1"
  local platform="$2"

  if ! launch_demo "$deployment_type" "$platform"; then
    bashunit::assertion_failed "demo to launch successfully on $platform with $deployment_type" "launch failed" "got"
    return
  fi

  bashunit::assertion_passed
}

function assert_demo_destroyed() {
  local platform="$1"

  if ! destroy_demo "$platform"; then
    bashunit::assertion_failed "demo to be destroyed on $platform" "destruction failed" "got"
    return
  fi

  bashunit::assertion_passed
}

function test_launch_demo_k8s() {
  assert_demo_launched "cloud-hosted" "k8s"
}

function test_destroy_demo_k8s() {
  assert_demo_destroyed "k8s"
}
