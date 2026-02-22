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

# Installs a Swift toolchain on Windows, including Visual Studio Build Tools.
#
# Environment variables (all set by the action step):
#   SWIFT_VERSION   Swift version, e.g. "6.2" or "nightly-main"
#   SDK_TYPE        Must be empty; SDK installation is not yet implemented on Windows
#   SCRIPT_ROOT     Absolute path to .github/workflows/scripts/windows/

$ErrorActionPreference = "Stop"

# SDK installation is not yet implemented on Windows
if (-not [string]::IsNullOrEmpty($env:SDK_TYPE)) {
    Write-Error "SDK installation on Windows is not yet implemented. The 'sdk' input is currently only supported on Linux."
    exit 1
}

Write-Host "Script root: $env:SCRIPT_ROOT"

# Install Visual Studio Build Tools if not already present
Write-Host "Checking for Visual Studio Build Tools..."
if (-not (Test-Path "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools")) {
    Write-Host "Installing Visual Studio Build Tools..."
    & "$env:SCRIPT_ROOT\install-vsb.ps1"
} else {
    Write-Host "Visual Studio Build Tools already installed, skipping."
}

# Delegate to the version-specific Swift installer
$installScript = "$env:SCRIPT_ROOT\swift\install-swift-$env:SWIFT_VERSION.ps1"
if (-not (Test-Path $installScript)) {
    Write-Error "No installation script found for Swift $env:SWIFT_VERSION at $installScript"
    exit 1
}

Write-Host "Installing Swift $env:SWIFT_VERSION..."
. $installScript

# Verify the installation
Write-Host "Verifying Swift installation..."
swift --version
if ($LASTEXITCODE -ne 0) {
    Write-Error "Swift installation verification failed"
    exit 1
}

Write-Host "Verifying Clang installation..."
clang --version
if ($LASTEXITCODE -ne 0) {
    Write-Error "Clang installation verification failed"
    exit 1
}
