# envcheck Architecture

## Overview

envcheck is a declarative development-environment validator and cautious bootstrap tool for Windows.

The architecture separates five concerns:

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

Configuration should describe the required capability:

```json
{
  "Name": "Node.js",
  "Command": "node",
  "Version": "18.x",
  "PackageId": "OpenJS.NodeJS.18",
  "Required": true
}
```

The configuration should not normally need to describe shell plumbing, output parsing, or installer command construction.

### Detection and remediation are separate

How software is detected is not necessarily how it is provisioned.

For the Node.js example:

```text
Detection
    resolve and execute node

Validation
    node --version must satisfy 18.x

Remediation
    package OpenJS.NodeJS.18
```

`Command` determines whether the software is usable. `PackageId` identifies the package envcheck may install if the command is genuinely missing.

### Registration is not health

A package-manager record is evidence that software was installed at some point. It is not proof that the executable, service, configuration, or dependent files remain usable.

envcheck therefore prefers functional checks where possible.

### Prefer diagnosis over destructive repair

When envcheck cannot confidently distinguish safe remediation from potentially destructive modification, envcheck reports the condition instead of changing the system.

## Configuration model

The preferred public configuration format is JSON:

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

`envcheck.schema.json` defines the current configuration contract. The schema uses descriptions, examples, and strict unknown-property rejection to provide useful editor validation and autocomplete.

The planned canonical versioned schema URI is:

```text
https://untapped.tech/envcheck/schema/v1.json
```

## Software requirements

A software requirement may use `Command`, `Service`, or `Path` as its primary detector. Those three properties are mutually exclusive.

`PackageId` has two roles:

- By itself, `PackageId` provides package-based detection and remediation.
- Alongside `Command`, `Service`, or `Path`, the other property controls detection while `PackageId` provides remediation metadata.

### Command detection

```json
{
  "Name": "Git",
  "Command": "git",
  "PackageId": "Git.Git",
  "Required": true
}
```

The command is resolved through `PATH` and executed for version detection. If the command is genuinely missing, `PackageId` identifies the package envcheck may install.

### Service detection

```json
{
  "Name": "MySQL",
  "Service": "MySQL",
  "Version": "8.4.x",
  "Required": true,
  "MustBeRunning": true
}
```

Service discovery resolves the Windows service, obtains its executable from `BinaryPathName`, validates the executable and version, and optionally validates service state.

Service-backed requirements remain entries in the top-level `Software` collection. There is no separate top-level `Services` collection.

### Path detection

```json
{
  "Name": "PHP",
  "Path": "C:\\tools\\php\\php.exe",
  "Version": "8.2.x",
  "Required": true
}
```

Path detection supports runtimes that intentionally are not globally available through `PATH`.

### Package-only detection

```json
{
  "Name": "PowerToys",
  "PackageId": "Microsoft.PowerToys",
  "Required": false
}
```

When no `Command`, `Service`, or `Path` is configured, envcheck detects the requirement through Winget package registration. The same `PackageId` is used for remediation.

### Detection constraints

Valid combinations include:

```text
Command
Command + PackageId
Service
Service + PackageId
Path
Path + PackageId
PackageId only
```

Invalid combinations include:

```text
Command + Service
Command + Path
Service + Path
```

A requirement with none of `Command`, `Service`, `Path`, or `PackageId` is a configuration error.

## Version subsystem

Version handling consists of three stages:

```text
Execute version command or inspect package version
        |
        v
Extract normalized version
        |
        v
Compare against requirement
```

### Default invocation

`--version` is the default argument for executable-backed version detection.

A requirement can override it:

```json
{
  "VersionArguments": ["--status"]
}
```

`VersionArguments` applies only to `Command`, `Service`, or `Path` detection.

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

Nonstandard executable output can use `VersionPattern`:

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

`VersionPattern` is an escape hatch for nonstandard output. Conventional software should continue using generic version extraction.

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

A plain `Version` is valid for package-only requirements because Winget can report an installed package version. `VersionArguments` and `VersionPattern` require executable-backed detection.

## Environment requirements

Environment-variable checks currently read variables visible to the running process:

```json
{
  "Name": "API_TOKEN",
  "Required": true,
  "Secret": true
}
```

Null, empty, and whitespace-only values do not satisfy a requirement. Secret values are redacted from output.

Future configuration sources may include dotenv files without changing the core requirement semantics.

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
PackageId
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

The exact set may evolve, but failure classification should remain explicit because remediation policy depends on it.

Winget remains an implementation provider in the PowerShell V0.x code, but Winget-specific source selection is not part of the public JSON configuration model.

## Broken-installation detection

A key architectural feature is distinguishing missing software from inconsistent package state:

```text
Command missing
      |
      v
PackageId configured?
      |
      v
Winget package installed?
      |
      +---- no ----> Missing
      |
      +---- yes ---> BrokenInstallation
```

A `BrokenInstallation` is deliberately not eligible for ordinary automatic bootstrap.

This prevents envcheck from treating a damaged package registration as though the software were simply absent.

## Remediation architecture

Read-only validation is the default. Bootstrap is explicitly requested by the user.

### Interactive bootstrap

```powershell
.\envcheck.ps1 -Bootstrap
```

envcheck asks before each eligible installation. Winget and the underlying installer remain interactive, so required source and package agreements are presented to the user and are not accepted automatically by envcheck.

### Fully approved bootstrap

```powershell
.\envcheck.ps1 -Bootstrap -Yes
```

`-Yes` authorizes:

1. all eligible package installations,
2. automatic acceptance of required Winget source and package agreements,
3. unattended/silent installation behavior.

`-Yes` has no effect without `-Bootstrap`.

The current CLI intentionally has only interactive bootstrap and fully approved bootstrap modes.

### Remediation safety matrix

| Condition                                 | Automatic remediation |
| ----------------------------------------- | --------------------- |
| Missing software with a known `PackageId` | May be offered        |
| Version mismatch                          | No                    |
| Broken installation                       | No                    |
| Invalid service state                     | No                    |
| Invalid envcheck configuration            | No                    |
| Version detection failure                 | No                    |

The configuration's `Version` is a validation requirement, not necessarily a package-manager installation version.

For example:

```json
{
  "Name": "Node.js",
  "Command": "node",
  "Version": "18.x",
  "PackageId": "OpenJS.NodeJS.18",
  "Required": true
}
```

must not cause envcheck to pass `--version 18.x` to Winget. `OpenJS.NodeJS.18` selects the Node 18 package family; envcheck independently validates that the resulting installed version satisfies `18.x`.

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

Unknown properties are rejected to catch mistakes such as:

```json
{
  "Requred": true
}
```

instead of silently ignoring the typo.

The schema uses:

- `description` for portable user-facing help,
- `examples` for representative values,
- `markdownDescription` selectively for richer editor help,
- `$comment` for maintainer-facing design notes,
- validation rules that mirror the current PowerShell implementation.

Schema changes must remain synchronized with `envcheck.ps1`, `envcheck.example.json`, the README, and relevant documentation.

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

The nested or per-platform package model may make sense in the Go version when multiple operating systems and package managers are actually supported. The PowerShell V0.x schema intentionally keeps a single flat `PackageId` because it supports only Winget.

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
