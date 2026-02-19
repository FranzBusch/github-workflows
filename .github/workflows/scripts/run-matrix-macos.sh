#!/bin/bash

set -euo pipefail

# This script runs a command on macOS with a specific Xcode version and custom environment variables
# Arguments:
#   $1: Xcode version
#   $2: Setup command (can be empty)
#   $3: Main command to run
#   $4: Command arguments (can be empty)
#   $5: JSON string of environment variables (can be empty)

xcode_version="$1"
setup_command="${2:-}"
command="$3"
command_arguments="${4:-}"
env_json="${5:-}"

# Select Xcode version
sudo xcode-select -s "/Applications/Xcode_${xcode_version}.app"

if [[ -n "$setup_command" ]]; then
  setup_command_expression="$setup_command &&"
else
  setup_command_expression=""
fi

# Export environment variables
if [[ -n "$env_json" && "$env_json" != '{}' ]]; then
  while IFS="=" read -r key value; do
    if [[ -n "$key" && -n "$value" ]]; then
      export "$key=$value"
    fi
  done < <(echo "$env_json" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
fi

echo "Executing command: $setup_command_expression $command $command_arguments"
bash -c "$setup_command_expression $command $command_arguments"
