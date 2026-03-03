#!/usr/bin/env bash

set -e -o pipefail

source "${CURRENT_DIR}/test/elastic/utils.sh"

function set_up_before_script() {
  start_local_elastic_stack
}

function tear_down_after_script() {
  uninstall_local_elastic_stack
}

function assert_docker_service_running() {
  local service="$1"

  if ! check_docker_service_running "$service"; then
    local status=$(docker ps --filter "name=^${service}$" --format '{{.Status}}' 2>/dev/null)
    local container_info=$(docker ps -a --filter "name=^${service}$" --format '{{.Status}}\t{{.Image}}' 2>/dev/null)

    if [[ -n "$container_info" ]]; then
      bashunit::assertion_failed "service '$service' to be running" "status: ${status:-not found}, details: $container_info" "got"
    else
      bashunit::assertion_failed "service '$service' to be running" "container does not exist" "got"
    fi
    return
  fi

  bashunit::assertion_passed
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

function test_launch_demo_docker() {
  assert_demo_launched "docker"
}

function test_check_docker_service_running() {
  local services=()
  mapfile -t services < <(docker compose config --services)

  for service in "${services[@]}"; do
    assert_docker_service_running "$service"
  done
}

function test_destroy_demo_docker() {
  assert_demo_destroyed "docker"
}
