#!/usr/bin/env bash

set -e -o pipefail

# Returns the HTTP status code from a call
# usage: get_http_response_code url username password
function get_http_response_code() {
    url=$1
    if [ -z "$url" ]; then
        echo "Error: you need to specify the URL for get the HTTP response"
        exit 1
    fi   
    username=$2
    password=$3

    if [ -z "$username" ] || [ -z "$password" ]; then
        result=$(curl -LI "$url" -o /dev/null -w '%{http_code}\n' -s)
    else
        result=$(curl -LI -u "$username":"$password" "$url" -o /dev/null -w '%{http_code}\n' -s)
    fi

    echo "$result"
}

function start_local_elastic_stack() {
    curl -fsSL https://elastic.co/start-local | sh
    source "${START_LOCAL_ENV_PATH}"
    sleep 2
    result=$(get_http_response_code "http://localhost:9200" "elastic" "${ES_LOCAL_PASSWORD}")
    assert_equals "200" "$result"
}

function uninstall_local_elastic_stack() {
    printf "yes\nno\n" | "${START_LOCAL_UNINSTALL_FILE}"
    rm -rf "${START_LOCAL_DIR}"
}

function launch_demo() {
    deployment_type="$1"
    platform="$2"
    elasticsearch_endpoint="${ES_LOCAL_URL:-$3}"
    elasticsearch_api_key="${ES_LOCAL_API_KEY}"
    printf "%s\n%s\n%s\n%s\n" "$deployment_type" "$platform" "$elasticsearch_endpoint" "$elasticsearch_api_key" | ./demo.sh
}

function destroy_demo() {
    platform="$1"
    printf "%s\n" "$platform" | ./demo.sh destroy
}