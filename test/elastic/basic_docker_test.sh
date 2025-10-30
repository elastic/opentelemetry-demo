#!/usr/bin/env bash

set -e -o pipefail

source "${CURRENT_DIR}/test/elastic/utils.sh"


function set_up_before_script() {
  start_local_elastic_stack
}

function tear_down_after_script() {
  uninstall_local_elastic_stack
}

function test_launch_demo_docker() { 
  result=$(launch_demo "cloud-hosted" "docker")
  assert_false "$result"
}

function test_destroy_demo_docker() { 
  result=$(destroy_demo "docker")
  assert_false "$result" 
}

