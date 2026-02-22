# This script runs Swift commands natively on Windows with custom environment variables
# Parameters:
#   -SwiftVersion: Swift version to use (e.g., "6.2", "nightly-main")
#   -SetupCommand: Setup command (can be empty)
#   -Command: Main command to run
#   -CommandArguments: JSON array or string of command arguments
#   -EnvJson: JSON string of environment variables (can be empty)
#   -NeedsToken: Boolean ("true"/"false") - if "true", passes GITHUB_TOKEN to environment

param(
    [Parameter(Mandatory=$true)]
    [string]$SwiftVersion,

    [Parameter(Mandatory=$false)]
    [string]$SetupCommand = "",

    [Parameter(Mandatory=$true)]
    [string]$Command,

    [Parameter(Mandatory=$false)]
    [string]$CommandArguments = "",

    [Parameter(Mandatory=$false)]
    [string]$EnvJson = "",

    [Parameter(Mandatory=$false)]
    [string]$NeedsToken = "false"
)

$ErrorActionPreference = "Stop"

# Determine script root (where the helper scripts are located)
if ($env:GITHUB_WORKSPACE) {
    if (Test-Path "$env:GITHUB_WORKSPACE\.github\workflows\scripts\windows") {
        $ScriptRoot = "$env:GITHUB_WORKSPACE\.github\workflows\scripts\windows"
    } elseif (Test-Path "$env:GITHUB_WORKSPACE\github-workflows\.github\workflows\scripts\windows") {
        $ScriptRoot = "$env:GITHUB_WORKSPACE\github-workflows\.github\workflows\scripts\windows"
    } else {
        Write-Error "Cannot find scripts directory"
        exit 1
    }
} else {
    $ScriptRoot = $PSScriptRoot
}

Write-Host "Script root: $ScriptRoot"

# Import helper functions from install-swift.ps1
. "$ScriptRoot\swift\install-swift.ps1"

# Verify Python is available (installed by workflow)
Write-Host "Verifying Python installation..."
if (-not (Get-Command python -ErrorAction SilentlyContinue)) {
    Write-Error "Python is not installed. The workflow should install Python before calling this script."
    exit 1
}
python --version

# Install Visual Studio Build Tools
Write-Host "Installing Visual Studio Build Tools..."
if (-not (Test-Path "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools")) {
    . "$ScriptRoot\install-vsb.ps1"
} else {
    Write-Host "Visual Studio Build Tools already installed, skipping..."
}

# Install Swift
Write-Host "Installing Swift $SwiftVersion..."
$swiftInstallScript = "$ScriptRoot\swift\install-swift-$SwiftVersion.ps1"
if (Test-Path $swiftInstallScript) {
    . $swiftInstallScript
} else {
    Write-Error "No installation script found for Swift $SwiftVersion at $swiftInstallScript"
    exit 1
}

# Verify Swift installation
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

# Set environment variables from JSON
if (-not [string]::IsNullOrEmpty($EnvJson) -and $EnvJson -ne '{}' -and $EnvJson -ne 'null') {
    Write-Host "Setting custom environment variables..."
    $env_obj = $EnvJson | ConvertFrom-Json
    if ($null -ne $env_obj) {
        $env_obj.PSObject.Properties | ForEach-Object {
            if (-not [string]::IsNullOrEmpty($_.Name) -and -not [string]::IsNullOrEmpty($_.Value)) {
                Write-Host "  $($_.Name)=$($_.Value)"
                Set-Item -Path "env:$($_.Name)" -Value $_.Value
            }
        }
    }
}

# Provide token if needed
if ($NeedsToken -eq "true" -and -not [string]::IsNullOrEmpty($env:GITHUB_TOKEN)) {
    Write-Host "GITHUB_TOKEN is available for use"
    # Token is already in environment, no need to set it again
}

# Convert command_arguments - support both array [], string, and null
$command_args_string = ""
if (-not [string]::IsNullOrEmpty($CommandArguments) -and $CommandArguments -ne 'null' -and $CommandArguments -ne '[]') {
    # Check if it's a JSON array
    if ($CommandArguments.Trim().StartsWith('[')) {
        $args_array = $CommandArguments | ConvertFrom-Json
        $command_args_string = $args_array -join ' '
    } else {
        # If it's a plain string, use as-is
        $command_args_string = $CommandArguments
    }
}

# Build the full command
$fullCommand = $Command
if (-not [string]::IsNullOrEmpty($command_args_string)) {
    $fullCommand = "$Command $command_args_string"
}

# Run setup command if provided
if (-not [string]::IsNullOrEmpty($SetupCommand)) {
    Write-Host "Running setup command: $SetupCommand"
    Invoke-Expression $SetupCommand
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Setup command failed with exit code $LASTEXITCODE"
        exit $LASTEXITCODE
    }
}

# Run the main command
Write-Host "Running command: $fullCommand"
Invoke-Expression $fullCommand
if ($LASTEXITCODE -ne 0) {
    Write-Error "Command failed with exit code $LASTEXITCODE"
    exit $LASTEXITCODE
}

Write-Host "Command completed successfully"
