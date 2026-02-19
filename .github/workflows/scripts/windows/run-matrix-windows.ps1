# This script runs a command in a Docker container with custom environment variables on Windows
# Parameters:
#   -Image: Docker image name
#   -SetupCommand: Setup command (can be empty)
#   -Command: Main command to run
#   -CommandArguments: JSON array or string of command arguments
#   -EnvJson: JSON string of environment variables (can be empty)

param(
    [Parameter(Mandatory=$true)]
    [string]$Image,

    [Parameter(Mandatory=$false)]
    [string]$SetupCommand = "",

    [Parameter(Mandatory=$true)]
    [string]$Command,

    [Parameter(Mandatory=$false)]
    [string]$CommandArguments = "",

    [Parameter(Mandatory=$false)]
    [string]$EnvJson = ""
)

$ErrorActionPreference = "Stop"

if (-not [string]::IsNullOrEmpty($SetupCommand)) {
    $setup_command_expression = "$SetupCommand &"
} else {
    $setup_command_expression = ""
}

$workspace = "C:\" + (Split-Path $env:GITHUB_WORKSPACE -Leaf)

$docker_args = @(
    "run", "-v", "$($env:GITHUB_WORKSPACE):$($workspace)",
    "-w", $workspace,
    "-e", "CI=$env:CI",
    "-e", "GITHUB_ACTIONS=$env:GITHUB_ACTIONS",
    "-e", "SWIFT_VERSION=$env:SWIFT_VERSION"
)

if (-not [string]::IsNullOrEmpty($EnvJson) -and $EnvJson -ne '{}' -and $EnvJson -ne 'null') {
    $env_obj = $EnvJson | ConvertFrom-Json
    if ($null -ne $env_obj) {
        $env_obj.PSObject.Properties | ForEach-Object {
            if (-not [string]::IsNullOrEmpty($_.Name) -and -not [string]::IsNullOrEmpty($_.Value)) {
                $docker_args += "-e"
                $docker_args += "$($_.Name)=$($_.Value)"
            }
        }
    }
}

# Convert command_arguments from JSON array to space-separated string
$command_args_string = ""
if (-not [string]::IsNullOrEmpty($CommandArguments) -and $CommandArguments -ne 'null') {
    # Check if it's a JSON array
    if ($CommandArguments.Trim().StartsWith('[')) {
        $args_array = $CommandArguments | ConvertFrom-Json
        $command_args_string = $args_array -join ' '
    } else {
        # If it's a plain string, use as-is
        $command_args_string = $CommandArguments
    }
}

$docker_args += @($Image, "cmd", "/s", "/c", "swift --version & $($setup_command_expression) $Command $command_args_string")

Write-Host "Executing Docker command: docker $($docker_args -join ' ')"
& docker @docker_args
