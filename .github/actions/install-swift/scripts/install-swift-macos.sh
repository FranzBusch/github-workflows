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

# Selects the appropriate Xcode toolchain on macOS based on a Swift version
# using a built-in version mapping table.
#
# Environment variables (all set by the action step):
#   SWIFT_VERSION      Swift version, e.g. "6.2"
#   SDK_TYPE           Must be empty; SDK installation is not supported on macOS
#   VERSION_MAP_FILE   Absolute path to swift-version-to-xcode.yml

log() { echo "** $*" >&2; }

# SDK installation is not supported on macOS
if [[ -n "${SDK_TYPE:-}" ]]; then
    log "ERROR: SDK installation is not supported on macOS."
    log "The 'sdk' input is only valid on Linux."
    exit 1
fi

# Look up the Xcode version for the requested Swift version
if [[ -z "${SWIFT_VERSION:-}" ]]; then
    log "ERROR: swift-version must be provided on macOS."
    exit 1
fi

xcode_version=$(yq e ".\"$SWIFT_VERSION\"" "$VERSION_MAP_FILE")
if [[ -z "$xcode_version" || "$xcode_version" == "null" ]]; then
    log "ERROR: No Xcode version mapping found for Swift $SWIFT_VERSION"
    log "Available Swift versions:"
    yq e 'keys | .[]' "$VERSION_MAP_FILE" >&2
    exit 1
fi
log "Mapped Swift $SWIFT_VERSION to Xcode $xcode_version"

log "Selecting Xcode $xcode_version"
sudo xcode-select -s "/Applications/Xcode_${xcode_version}.app"

# Export the resolved Xcode version for subsequent steps
echo "xcode-version=$xcode_version" >> "$GITHUB_OUTPUT"

echo "Swift version:"
xcrun swift --version

echo "Clang version:"
xcrun clang --version
