#!/bin/bash

set -euo pipefail

# This script runs a command in a Docker container with custom environment variables
# Arguments:
#   $1: Docker image name
#   $2: Setup command (can be empty)
#   $3: Main command to run
#   $4: Command arguments (can be empty)
#   $5: JSON string of environment variables (can be empty)

image="$1"
setup_command="${2:-}"
command="$3"
command_arguments="${4:-}"
env_json="${5:-}"

if [[ -n "$setup_command" ]]; then
  setup_command_expression="$setup_command &&"
else
  setup_command_expression=""
fi

workspace="/$(basename "$GITHUB_WORKSPACE")"

docker_args=(
  "run"
  "-v" "$GITHUB_WORKSPACE:$workspace"
  "-w" "$workspace"
  "-e" "CI=$CI"
  "-e" "GITHUB_ACTIONS=$GITHUB_ACTIONS"
  "-e" "SWIFT_VERSION=${SWIFT_VERSION:-}"
  "-e" "workspace=$workspace"
)

if [[ -n "$env_json" && "$env_json" != '{}' ]]; then
  while IFS="=" read -r key value; do
    if [[ -n "$key" && -n "$value" ]]; then
      docker_args+=("-e" "$key=$value")
    fi
  done < <(echo "$env_json" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
fi

docker_args+=("$image")
docker_args+=("bash" "-c" "$setup_command_expression $command $command_arguments")

echo "Executing Docker command: docker ${docker_args[*]}"
docker "${docker_args[@]}"
