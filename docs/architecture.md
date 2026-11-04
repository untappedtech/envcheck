# envcheck Architecture

## Overview

envcheck is a declarative development-environment validator and cautious bootstrap tool for Windows.

The architecture is built around a simple separation:

```text
Configuration
    defines intended state

Detection
    determines observed state

Validation
    compares observed state with intended state

Reporting
    explains the result

Remediation
    optionally changes only states that are safe to change automatically
```

The current implementation is a PowerShell prototype. The prototype exists to stabilize the domain model before a future strongly typed implementation is considered.

## Core design principles

### Configuration describes intent

Configuration should describe the requirement:

```json
{
  "Name": "Node.js",
  "Command": "node",
  "Version": "18.x",
  "Required": true,
  "WingetId": "OpenJS.NodeJS.18"
}
```

The configuration should not normally need to describe shell plumbing, output parsing, or installer command construction.

### Detection and remediation are separate

How software is detected is not necessarily how software is provisioned.

In the Node example:

```text
Detection
    Get-Command node

Validation
    node --version must satisfy 18.x

Remediation
    Winget package OpenJS.NodeJS.18
```

### Registration is not health

A package-manager record is evidence that software was installed at some point. It is not proof that the executable, service, configuration, or dependent files remain usable.

envcheck therefore prefers functional checks where possible.

### Prefer diagnosis over destructive repair

When envcheck cannot confidently distinguish safe remediation from potentially destructive modification, it reports the condition instead of changing the system.

## Configuration model

The preferred public configuration format is JSON.

```json
{
  "$schema": "./envcheck.schema.json",
  "Name": "Example Development Environment",
  "Software": [],
  "Environment": [],
  "Files": [],
  "Connectivity": []
}
```

The configuration schema is defined by `envcheck.schema.json`.

## Software requirements

Each software requirement uses exactly one detection strategy.

### Command

```json
{
  "Name": "Git",
  "Command": "git",
  "Required": true,
  "WingetId": "Git.Git"
}
```

The command is resolved through the shell and executed for version detection.

### Service

```json
{
  "Name": "MySQL",
  "Service": "MySQL",
  "Version": "8.4.x",
  "Required": true,
  "MustBeRunning": true
}
```

Service discovery resolves the Windows service, obtains the executable from `BinaryPathName`, validates the executable and version, then optionally validates service state.

### Path

```json
{
  "Name": "PHP",
  "Path": "C:\\tools\\php\\php.exe",
  "Version": "8.2.x",
  "Required": true
}
```

Path detection supports runtimes that intentionally are not globally available through `PATH`.

### WingetPackage

```json
{
  "Name": "Visual C++ 2013 Redistributable x64",
  "WingetPackage": "Microsoft.VCRedist.2013.x64",
  "Required": true
}
```

This strategy uses package registration as the requirement itself. The same package ID is the default remediation identity.

### Mutual exclusivity

These properties are mutually exclusive:

```text
Command
Service
Path
WingetPackage
```

Zero strategies is a configuration error. More than one strategy is ambiguous and is also a configuration error.

## Version subsystem

Version handling consists of three stages:

```text
Execute version command
        |
        v
Extract normalized version
        |
        v
Compare against requirement
```

### Default invocation

`--version` is the default version argument.

A requirement can override it:

```json
{
  "VersionArguments": ["--status"]
}
```

### Generic extraction

The generic parser prefers detailed dotted versions such as:

```text
18.20.8
8.4.9
1.2.3.4
```

and falls back to two-component versions such as:

```text
8.4
3.12
```

Common prefixes such as `v` and `go` are ignored.

### Custom extraction

Nonstandard output can use `VersionPattern`:

```json
{
  "Name": "WSL 2",
  "Command": "wsl",
  "VersionArguments": ["--status"],
  "VersionPattern": "Default Version:\\s*(?<version>\\d+)",
  "Version": "2",
  "Required": true
}
```

The regular expression must provide a named `version` capture group.

Native command output is normalized before parsing. This includes removing embedded NUL characters that some Windows commands can emit when their console output is captured.

### Version matching

Exact matching:

```text
18.20.8 matches 18.20.8
```

Trailing wildcard matching:

```text
18.20.8 matches 18.x
8.4.9 matches 8.4.x
8.5.0 does not match 8.4.x
```

Full semantic-version constraint expressions are intentionally not implemented yet.

## Environment requirements

Environment-variable checks currently read variables visible to the running process.

```json
{
  "Name": "API_TOKEN",
  "Required": true,
  "Secret": true
}
```

Null, empty, and whitespace-only values do not satisfy a requirement.

Secret values are redacted from output.

Future configuration sources may include dotenv files without changing the requirement semantics.

## File requirements

```json
{
  "Name": "Application configuration",
  "Path": ".env",
  "Required": true
}
```

A file requirement currently checks:

1. the path exists,
2. the path is a file,
3. the file size is greater than zero bytes.

## Connectivity requirements

```json
{
  "Name": "Local database",
  "Host": "localhost",
  "Port": 3306,
  "TimeoutMs": 3000,
  "Required": true
}
```

The current connectivity implementation verifies TCP reachability only.

Protocol authentication and application health are separate future concerns.

## Result model

Checks are normalized into a common result model containing information such as:

```text
Status
Category
Name
Message
Required
WingetId
WingetSource
ExpectedVersion
FailureKind
```

Statuses:

```text
PASS
WARN
FAIL
```

Failure classifications currently include:

```text
Missing
VersionMismatch
BrokenInstallation
VersionDetection
ServiceState
Configuration
ServiceExecutable
WingetUnavailable
EmptyFile
```

The exact list may evolve, but failure classification should remain explicit because remediation policy depends on it.

## Broken-installation detection

A key architectural feature is distinguishing missing software from inconsistent package state.

```text
Command missing
      |
      v
Winget remediation configured?
      |
      v
Winget package installed?
      |
      +---- no ----> Missing
      |
      +---- yes ---> BrokenInstallation
```

A `BrokenInstallation` is deliberately not eligible for ordinary automatic bootstrap.

## Remediation architecture

Read-only validation is the default.

Bootstrap is explicitly requested by the user.

The intended safety matrix is:

| Condition | Automatic remediation |
|---|---|
| Missing software with known Winget package | May be offered |
| Version mismatch | No |
| Broken installation | No |
| Invalid service state | No |
| Invalid envcheck configuration | No |
| Version detection failure | No |

The configuration's `Version` is a validation requirement, not necessarily a package-manager installation version.

For example:

```json
{
  "Name": "Node.js",
  "Command": "node",
  "Version": "18.x",
  "WingetId": "OpenJS.NodeJS.18"
}
```

should not cause envcheck to pass `--version 18.x` to Winget.

## Configuration loading

The intended precedence is:

```text
explicit -Config path
        |
        v
./envcheck.json
        |
        v
embedded fallback configuration
```

External JSON is the preferred public interface.

## Schema

The repository JSON Schema serves three purposes:

1. editor validation,
2. autocomplete and discoverability,
3. an explicit machine-readable configuration contract.

Unknown properties are rejected to catch errors such as:

```json
{
  "Requred": true
}
```

instead of silently ignoring the typo.

## Future Go architecture

The eventual Go implementation should preserve the concepts discovered by the PowerShell prototype rather than merely translating functions line for line.

A likely package structure is:

```text
config/
    loading
    validation
    schema/version compatibility

requirements/
    command
    path
    service
    package
    environment
    file
    connectivity
    platform

version/
    extraction
    normalization
    matching

providers/
    winget
    future package managers

reporting/
    console
    json

remediation/
    planning
    consent
    execution
```

Detection strategies should become explicit types rather than one large structure containing many optional fields.

## Architectural boundaries to preserve

Keep these concepts separate:

```text
Detection
    How do we observe the capability?

Validation
    Does the observed state satisfy the requirement?

Remediation
    Can envcheck safely move the machine toward the desired state?

Dependencies
    What requirements must be satisfied before others?

Configuration sources
    Where does expected configuration data come from?
```

Collapsing these concerns together would recreate the complexity envcheck is intended to remove.
