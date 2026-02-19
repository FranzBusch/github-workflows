#!/bin/bash

set -euo pipefail

# This script runs a command on macOS with a specific Xcode version and custom environment variables
# Arguments:
#   $1: Xcode version
#   $2: Setup command (can be empty)
#   $3: Main command to run
#   $4: JSON array or string of command arguments
#   $5: JSON string of environment variables (can be empty)

xcode_version="$1"
setup_command="${2:-}"
command="$3"
command_arguments_json="${4:-}"
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

# Convert command_arguments from JSON array to space-separated string
if [[ -n "$command_arguments_json" && "$command_arguments_json" != "null" ]]; then
  # Check if it's an array by testing if it starts with [
  if [[ "$command_arguments_json" =~ ^\[.*\]$ ]]; then
    command_arguments=$(echo "$command_arguments_json" | jq -r 'join(" ")')
  else
    # If it's a plain string, use as-is
    command_arguments="$command_arguments_json"
  fi
else
  command_arguments=""
fi

echo "Executing command: $setup_command_expression $command $command_arguments"
bash -c "$setup_command_expression $command $command_arguments"
