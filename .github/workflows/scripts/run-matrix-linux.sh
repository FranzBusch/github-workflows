#!/bin/bash

set -euo pipefail

# This script runs commands natively on a Linux host using swiftly to install Swift
# Arguments:
#   $1: Swift version (e.g., "6.2", "nightly-main")
#   $2: Setup command (can be empty)
#   $3: Main command to run
#   $4: JSON array or string of command arguments
#   $5: JSON string of environment variables (can be empty)
#   $6: needs_token (true/false, optional) - if "true", GITHUB_TOKEN is available
#   $7: SDK JSON configuration (optional) - if provided, installs SDK and adds --swift-sdk to command

swift_version="$1"
setup_command="${2:-}"
command="$3"
command_arguments_json="${4:-}"
env_json="${5:-}"
needs_token="${6:-false}"
sdk_json="${7:-}"

log() { echo "** $*" >&2; }

# Install swiftly if not present
install_swiftly() {
    if command -v swiftly &> /dev/null; then
        log "Swiftly is already installed"
        return 0
    fi

    log "Installing swiftly..."

    # Download and extract swiftly
    curl -fsSL -O "https://download.swift.org/swiftly/linux/swiftly-$(uname -m).tar.gz"
    tar zxf "swiftly-$(uname -m).tar.gz"

    # Initialize swiftly without installing a toolchain
    ./swiftly init --quiet-shell-followup --skip-install --assume-yes

    # Source swiftly environment
    source "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
    hash -r

    # Clean up
    rm -f "swiftly-$(uname -m).tar.gz"
    rm -f swiftly

    log "Swiftly installed successfully"
}

# Install Swift using swiftly
install_swift() {
    local version="$1"

    # Map version format for swiftly
    local swiftly_version=""
    if [[ "$version" == nightly-* ]]; then
        local branch="${version#nightly-}"
        if [[ "$branch" == "main" ]]; then
            swiftly_version="main-snapshot"
        else
            # For nightly-6.3, use 6.3-snapshot
            swiftly_version="${branch}-snapshot"
        fi
    else
        # For release versions like "6.2", use as-is
        swiftly_version="$version"
    fi

    log "Installing Swift $swiftly_version using swiftly..."

    local post_install_file="/tmp/swiftly-post-install.sh"

    # Install Swift with post-install file
    swiftly install "$swiftly_version" --use --post-install-file="$post_install_file"

    # Check if post-install file exists and has content
    if [[ -f "$post_install_file" && -s "$post_install_file" ]]; then
        log "Running post-install commands..."
        cat "$post_install_file"
        sudo bash "$post_install_file"
        rm -f "$post_install_file"
    fi

    log "Swift installed successfully"
    swift --version
}

# Install swiftly
install_swiftly

# Source swiftly environment to ensure swift is in PATH
source "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/env.sh"
hash -r

# Install Swift
install_swift "$swift_version"

# Handle environment variables
if [[ -n "$env_json" && "$env_json" != '{}' && "$env_json" != 'null' ]]; then
    while IFS="=" read -r key value; do
        if [[ -n "$key" && -n "$value" ]]; then
            export "$key=$value"
        fi
    done < <(echo "$env_json" | jq -r 'to_entries[] | "\(.key)=\(.value)"')
fi

# Convert command_arguments
command_arguments=""
if [[ -n "$command_arguments_json" && "$command_arguments_json" != "null" && "$command_arguments_json" != '[]' ]]; then
    if [[ "$command_arguments_json" =~ ^\[.*\]$ ]]; then
        command_arguments=$(echo "$command_arguments_json" | jq -r 'join(" ")')
    else
        command_arguments="$command_arguments_json"
    fi
fi

# Handle SDK installation
sdk_install_command=""
if [[ -n "$sdk_json" && "$sdk_json" != "null" && "$sdk_json" != '{}' ]]; then
    sdk_type=$(echo "$sdk_json" | jq -r '.type // empty')

    if [[ -n "$sdk_type" ]]; then
        log "Will install SDK: $sdk_type"

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
                log "Error: Unknown SDK type: $sdk_type"
                exit 1
                ;;
        esac

        sdk_install_command="SDK_NAME=\$($sdk_install_cmd) && "

        if [[ "$sdk_type" == "android" ]]; then
            first_triple=$(echo "$sdk_json" | jq -r '.triples[0]')
            command="$command --swift-sdk $first_triple"
        else
            command="$command --swift-sdk \$SDK_NAME"
        fi
    fi
fi

# Build full command
setup_expr=""
if [[ -n "$setup_command" ]]; then
    setup_expr="$setup_command &&"
fi

full_command="$sdk_install_command $setup_expr $command $command_arguments"

log "Executing command: $full_command"
eval "$full_command"
