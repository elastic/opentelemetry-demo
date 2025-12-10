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
  launch_demo "cloud-hosted" "docker"
}

function test_check_docker_service_running() { 
  local services=($docker compose config --services)

  for service in "${services[@]}"; do
    assert_exit_code "0" "$(check_docker_service_running "$service")"
  done
}

function test_destroy_demo_docker() { 
  destroy_demo "docker"
}

