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
  local platform="$1"

  if ! launch_demo "$platform"; then
    bashunit::assertion_failed "demo to launch successfully on $platform" "launch failed" "got"
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
  # TODO: Re-enable once the helm charts have been updated
  # for k8s in elastic agent, at present k8s fails due to a helm mapping null to missing fields
  # This PR fixes the issue -> https://github.com/elastic/elastic-agent/pull/11481
  bashunit::skip "K8s test disabled: helm chart null mapping issue" && return

  assert_demo_launched "k8s"
}

function test_destroy_demo_k8s() {
  # TODO: Re-enable once the helm charts have been updated
  # for k8s in elastic agent, see above comment for more info.
  bashunit::skip "K8s test disabled: helm chart null mapping issue" && return

  assert_demo_destroyed "k8s"
}
