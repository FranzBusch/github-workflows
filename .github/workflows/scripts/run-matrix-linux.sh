#!/bin/bash

set -euo pipefail

# This script runs a command in a Docker container with custom environment variables
# Arguments:
#   $1: Docker image name
#   $2: Setup command (can be empty)
#   $3: Main command to run
#   $4: JSON array or string of command arguments
#   $5: JSON string of environment variables (can be empty)
#   $6: needs_token (true/false, optional) - if "true", passes GITHUB_TOKEN to container
#   $7: SDK JSON configuration (optional) - if provided, installs SDK and adds --swift-sdk to command

image="$1"
setup_command="${2:-}"
command="$3"
command_arguments_json="${4:-}"
env_json="${5:-}"
needs_token="${6:-false}"
sdk_json="${7:-}"

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

# Provide token if needed
if [[ "$needs_token" == "true" && -n "${GITHUB_TOKEN:-}" ]]; then
  docker_args+=("-e" "GITHUB_TOKEN=$GITHUB_TOKEN")
fi

# Handle environment variables - support both object {} and null
if [[ -n "$env_json" && "$env_json" != '{}' && "$env_json" != 'null' ]]; then
  while IFS="=" read -r key value; do
    if [[ -n "$key" && -n "$value" ]]; then
      docker_args+=("-e" "$key=$value")
    fi
  done < <(echo "$env_json" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
fi

# Convert command_arguments - support both array [], string, and null
command_arguments=""
if [[ -n "$command_arguments_json" && "$command_arguments_json" != "null" && "$command_arguments_json" != '[]' ]]; then
  # Check if it's an array by testing if it starts with [
  if [[ "$command_arguments_json" =~ ^\[.*\]$ ]]; then
    command_arguments=$(echo "$command_arguments_json" | jq -r 'join(" ")')
  else
    # If it's a plain string, use as-is
    command_arguments="$command_arguments_json"
  fi
fi

# Handle SDK installation and configuration
sdk_install_command=""
if [[ -n "$sdk_json" && "$sdk_json" != "null" && "$sdk_json" != '{}' ]]; then
  sdk_type=$(echo "$sdk_json" | jq -r '.type // empty')

  if [[ -n "$sdk_type" ]]; then
    echo "Will install SDK: $sdk_type"

    # Build SDK installation command based on type
    case "$sdk_type" in
      static-linux)
        sdk_install_cmd="./.github/workflows/scripts/install-and-build-with-sdk.sh --static --install-only \${SWIFT_VERSION}"
        ;;
      wasm)
        sdk_install_cmd="./.github/workflows/scripts/install-and-build-with-sdk.sh --wasm --install-only \${SWIFT_VERSION}"
        ;;
      wasm-embedded)
        sdk_install_cmd="./.github/workflows/scripts/install-and-build-with-sdk.sh --embedded-wasm --install-only \${SWIFT_VERSION}"
        ;;
      android)
        ndk_version=$(echo "$sdk_json" | jq -r '.ndk_version // "r27d"')
        triples=$(echo "$sdk_json" | jq -r '.triples[]?' | sed 's/^/--android-sdk-triple=/' | tr '\n' ' ')
        sdk_install_cmd="./.github/workflows/scripts/install-and-build-with-sdk.sh --android --android-ndk-version=$ndk_version $triples --install-only \${SWIFT_VERSION}"
        ;;
      *)
        echo "Error: Unknown SDK type: $sdk_type" >&2
        exit 1
        ;;
    esac

    # Capture SDK name in a variable and append --swift-sdk to command
    sdk_install_command="SDK_NAME=\$($sdk_install_cmd) && "

    if [[ "$sdk_type" == "android" ]]; then
      # For Android, use the first triple
      first_triple=$(echo "$sdk_json" | jq -r '.triples[0]')
      command="$command --swift-sdk $first_triple"
    else
      command="$command --swift-sdk \$SDK_NAME"
    fi
  fi
fi

docker_args+=("$image")
docker_args+=("bash" "-c" "$sdk_install_command $setup_command_expression $command $command_arguments")

echo "Executing Docker command: docker ${docker_args[*]}"
docker "${docker_args[@]}"
