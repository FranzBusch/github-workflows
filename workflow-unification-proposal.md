# Swift workflow unification

## Introduction

This proposal outlines a plan to unify the Github action workflows from
[apple/swift-nio](https://github.com/apple/swift-nio/tree/main/.github/workflows)
and
[swiftlang/github-workflows](https://github.com/swiftlang/github-workflows/tree/main/.github/workflows)
into a single, solution in the `github-workflows` repository.

## Motivation

We currently have two different reusable workflows that packages can use. This
is duplicating the maintenance burden and provides a different contributor
experience across projects. Additionally, both reusable workflow setups have
slightly different capabilities.

## Current State

This section outlines the current approach and capabilities of the current
solutions:

### swift-nio workflows

- Uses a dynamic matrix generation via `generate_matrix.sh`
- Uses curl based pulling of the scripts
- Offers an automatic minimum Swift version detection from `Package.swift`
- Per-swift-version command argument overrides
- Testing is split into multiple separate workflows: `unit_tests.yml`,
  `macos_tests.yml`, and various Swift SDK tests for Android, WASM and the MUSL
  SDK

### github-workflows

- Single monolithic `swift_package_test.yml` workflow that covers all platforms
- Uses git checkout based pulling of the scripts
- JSON array-based matrix inputs (manual configuration)
- Individual job enable/disable flags

## Unified requirements

Since both approaches have evolved over time and applied learnings along the
way. It is good to reflect what worked well and what didn't. The following
section covers the requirements that a unified solution must offer to replace
either of the current solutions.

### 1. Github release based versioning

Workflows and actions must be versioned using the Github releases to guarantee
stability to adopters. Furthermore, this allows the usage of Dependabot to
automatically open PRs to workflows. Lastly, it also enables rolling out
breaking changes since it only breaks adopters once they migrate.

### 2. Scripts must be cloned not curled

Some jobs rely on scripts to execute their functionality. This is often
preferred over inline scripts in the yml files since it gives a better developer
experience to the maintainers of those scripts. However, one downside of this
approach is that these scripts are not present when a reusable workflow is
executed from another repository. It is important that a unified solution uses
git clone explicitly or uses a local action instead of curling the script.
Curling frequently runs into rate limiting with Github's API.

### 3. No skipped jobs

No reusable workflow offered should end up in showing skipped jobs. Skipped jobs
look confusing to contributors and imply that something is configured
incorrectly.

### 4. Single reusable recommended test workflow for packages

There should be a single workflow that packages can call that runs all the
recommended jobs. The recommend jobs at the moment contain:
- Running `swift test` in debug mode for
  - The latest patch release of the last three minor official Swift releases.
  - All officially supported platforms of Swift that support testing.
- Running `swift build` for any platform that doesn't support testing
- Running `swift build` in release mode for at least one platform (at this point
  Ubuntu 24.04)
- Building with Cxx interop

This single workflow needs to provide overrides for configuring:
1. A command that runs before the action i.e. before `swift test` or `swift
   build`
2. A way to provide additional arguments to the action e.g. passing
   `-warnings-as-errors`
3. A way to provide additional environment variables that are passed to the
   action e.g. setting custom configuration values

Importantly, these overrides need to be configurable on a per platform and per
Swift version level. Concretely, it must be possible to use the reusable test
workflow and add an additional argument for Windows with Swift 6.2.0, or set a
specific environment variable only for Linux with Swift 6.0.

### 5. Custom matrix builds

Some packages need to run additional checks such as running their custom
integration tests or running a custom script. Those checks often need to run
across a similar matrix of builds as the reusable test workflow in (2). Hence, a
unified solution should offer lower level primitives that can execute a matrix.
Furthermore, it should provide a workflow with a matrix that is already
configured with the recommended Swift versions and platforms that just executes
a command across them.

### 6. Detect minimum version

Any matrix that is generated should take the tools-version of the package
manifest into consideration to automatically remove unsupported Swift versions.
That's critically important for newly released packages which often only support
the latest Swift version.

## Proposed Plan

I propose to unify the two approaches into a single approach that combines the
benefits of both. This approach takes inspiration from both current workflow
solutions while ensuring that the above unified requirements are met.

### Matrix definition

At the bottom of the proposed approach is a similar matrix generation that the
NIO workflows employ. This is the only way to avoid skipped jobs. Furthermore,
it allows higher level workflows to generate default matrices. The matrix is
defined in YAML which allows it to be either stored inside the repositories or
dynamically generated. Below is the specification of a matrix:

```yaml
config:
  # This is a linux host platform based job. Below are all the valid keys
  - platform: Linux
    name: Swift 6.0
    runner:
      - ubuntu-latest
    swift_version: "6.0"
    os: jammy  # Used to find the right docker image
    setup_command: uname -a
    command: swift test
    command_arguments:
      - -Xswiftc
      - -warnings-as-errors
    env:
      CUSTOM_VAR: value
      ANOTHER_VAR: another_value
  # This is a windows host platform based job. Below are all the valid keys
  - platform: Windows
    name: Swift 6.0
    runner:
      - windows-latest
    swift_version: "6.0"
    setup_command: echo "Starting tests"
    command: swift test
    command_arguments:
      - -Xswiftc
      - -warnings-as-errors
    env:
      CUSTOM_VAR: value
  # This is a macOS host platform based job. Below are all the valid keys
  - platform: macOS
    name: Xcode 26.2
    runner:
      - macos
      - tahoe
      - ARM64
      - general
    xcode_version: "26.2"
    setup_command: uname -a
    command: swift test
    command_arguments:
      - -Xswiftc
      - -warnings-as-errors
    env:
      CUSTOM_VAR: value
```
### Matrix generation

The matrix is executed by a simple workflow:

```yaml
name: Matrix

permissions:
  contents: read

on:
  workflow_call:
    inputs:
      name:
        type: string
        description: "The name of the workflow used for the concurrency group."
        required: true
      matrix_string:
        type: string
        description: "The test matrix definition."
        required: true

# We will cancel previously triggered workflow runs
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}-${{ inputs.name }}
  cancel-in-progress: true

jobs:
  execute-matrix:
    if: needs.construct-matrix.outputs.has-jobs == 'true'
    needs: construct-matrix
    name: ${{ matrix.config.name }}
    runs-on: ${{ matrix.config.runner }}
    strategy:
      matrix: ${{ fromJson(needs.construct-matrix.outputs.matrix) }}
    steps:
      - if: runner.os == 'Linux"
        run: docker run ...
      - if: runner.os == 'macOS"
        run: xcrun swift test ...
      - if: runner.os == 'Windows"
        run: docker run ... (or native)
```

## Future Directions

### Benchmark Workflow

### CMake Workflow



### Migration strategy 


TODO: YML migration
TODO: To scripts instead of inline
TODO: Provide a default workflow and document the upgrade story for adopter packages