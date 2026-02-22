#!/bin/bash
##===----------------------------------------------------------------------===##
##
## This source file is part of the Swift.org open source project
##
## Copyright (c) 2025 Apple Inc. and the Swift project authors
## Licensed under Apache License v2.0 with Runtime Library Exception
##
## See https://swift.org/LICENSE.txt for license information
## See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
##
##===----------------------------------------------------------------------===##

set -euo pipefail

# Installs a Swift toolchain on Linux via swiftly and optionally installs a
# Swift SDK for cross-compilation.
#
# Environment variables (all set by the action step):
#   SWIFT_VERSION          Swift version, e.g. "6.2" or "nightly-main"
#   SDK_TYPE               Optional. One of: static-linux, wasm, wasm-embedded, android
#   SDK_NDK_VERSION        Android NDK version, e.g. "r27d" (android only)
#   SDK_ANDROID_TRIPLES    Space-separated Android triples (android only)
#   SDK_SCRIPT             Absolute path to install-and-build-with-sdk.sh

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
install_swift "$SWIFT_VERSION"

# Propagate swiftly's bin path to subsequent composite action steps.
# Each step in a composite action runs in an isolated shell, so PATH changes
# made inside this script are not visible to later steps without this export.
echo "${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}/bin" >> "$GITHUB_PATH"
echo "SWIFTLY_HOME_DIR=${SWIFTLY_HOME_DIR:-$HOME/.local/share/swiftly}" >> "$GITHUB_ENV"

# Install SDK if requested
if [[ -n "${SDK_TYPE:-}" ]]; then
    log "Installing SDK: $SDK_TYPE"

    sdk_name=""
    case "$SDK_TYPE" in
        static-linux)
            sdk_name=$("$SDK_SCRIPT" --static --install-only "$SWIFT_VERSION")
            ;;
        wasm)
            sdk_name=$("$SDK_SCRIPT" --wasm --install-only "$SWIFT_VERSION")
            ;;
        wasm-embedded)
            sdk_name=$("$SDK_SCRIPT" --embedded-wasm --install-only "$SWIFT_VERSION")
            ;;
        android)
            triples_flags=""
            for triple in ${SDK_ANDROID_TRIPLES:-}; do
                triples_flags="$triples_flags --android-sdk-triple=$triple"
            done
            "$SDK_SCRIPT" --android \
                --android-ndk-version="${SDK_NDK_VERSION:-r27d}" \
                $triples_flags \
                --install-only "$SWIFT_VERSION" > /dev/null
            # Swift requires a full triple as the --swift-sdk argument for Android,
            # not the base SDK name that install-and-build-with-sdk.sh outputs.
            # Use the first triple from the input list.
            sdk_name="${SDK_ANDROID_TRIPLES%% *}"
            ;;
        *)
            log "ERROR: Unknown SDK type: $SDK_TYPE"
            exit 1
            ;;
    esac

    log "SDK installed: $sdk_name"
    echo "sdk-name=$sdk_name" >> "$GITHUB_OUTPUT"
fi
