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
    local all_containers=$(docker ps -a --format '{{.Names}}')
    
    local actual_name=$(docker ps -a --filter "name=${service}" --format '{{.Names}}' | head -1)
    local status=$(docker ps -a --filter "name=${service}" --format '{{.Status}}' | head -1)
    local container_info=$(docker ps -a --filter "name=${service}" --format '{{.Status}}\t{{.Image}}' | head -1)
    
    local logs="NO CONTAINER FOUND"
    if [[ -n "$actual_name" ]]; then
      logs="CONTAINER: $actual_name, LOGS: $(docker logs "$actual_name" 2>&1 | tail -20)"
    fi
    
    bashunit::assertion_failed "service '$service' to be running" "status: ${status:-not found}, actual_name: ${actual_name:-none}, details: $container_info, logs: $logs, all_containers: $all_containers" "got"
    return
  fi

  bashunit::assertion_passed
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

function test_launch_demo_docker() {
  assert_demo_launched "cloud-hosted" "docker"
}

function test_check_docker_service_running() {
  local services=($(docker compose config --services))

  for service in "${services[@]}"; do
    assert_docker_service_running "$service"
  done
}

function test_destroy_demo_docker() {
  assert_demo_destroyed "docker"
}
