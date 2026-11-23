# envcheck

Declarative development-environment validation and cautious bootstrap for Windows.

`envcheck` answers a simple question:

> Does this machine actually satisfy the requirements for this development environment?

Rather than relying only on package-manager registration, `envcheck` validates the capabilities developers actually depend on: executable commands, versions, Windows services, package registrations, environment variables, files, and network endpoints.

When something is genuinely missing, `envcheck` can optionally use Winget to bootstrap it. When something appears installed but is unusable, `envcheck` reports the inconsistency instead of blindly attempting another installation.

## Why envcheck?

Development environments tend to accumulate hidden assumptions:

- Install Node.js.
- Use PHP 8.2, not whichever PHP happens to appear first on `PATH`.
- Make sure the database service is running.
- Use WSL 2.
- Copy the `.env` file.
- Install the required Visual C++ runtimes first.

Those expectations usually live in setup documents, chat history, individual memory, or nowhere at all.

Package managers answer only part of the question. A package can be registered as installed while its executable is missing. A Windows service can exist but be stopped. The wrong runtime can win `PATH` resolution. A required file can exist but contain zero bytes.

`envcheck` makes those expectations explicit and executable.

## Status

`envcheck` is currently an early PowerShell prototype for Windows.

The prototype is being used to stabilize the configuration model, validation semantics, failure classifications, and safe remediation behavior before a larger implementation is considered. The configuration format and command-line interface may evolve.

## Quick start

Copy the example configuration:

```powershell
Copy-Item .\envcheck.example.json .\envcheck.json
```

Edit `envcheck.json` to describe the environment, then run:

```powershell
.\envcheck.ps1
```

External JSON configuration is the recommended way to use envcheck. Embedded PowerShell configuration exists primarily as a fallback and for development or testing.

## Configuration loading

Use an explicit configuration path:

```powershell
.\envcheck.ps1 -Config .\envcheck.json
```

When `-Config` is omitted, envcheck looks for:

```text
.\envcheck.json
```

If no external configuration exists, the script can fall back to its embedded configuration.

A typical configuration describes:

```text
Development Environment
├── Software
│   ├── commands
│   ├── services
│   ├── explicit paths
│   └── package IDs
├── Environment variables
├── Files
└── Connectivity
```

## Software detection

A software requirement can use `Command`, `Service`, or `Path` as its primary detector. These three properties are mutually exclusive.

`PackageId` has two roles:

- By itself, `PackageId` is used for Winget package detection and remediation.
- With `Command`, `Service`, or `Path`, that property controls detection while `PackageId` identifies the Winget package envcheck may install when the requirement is genuinely missing.

### Command

Resolve and execute a command available through `PATH`:

```json
{
  "Name": "Git",
  "Command": "git",
  "Required": true,
  "PackageId": "Git.Git"
}
```

### Windows service

Resolve software through a Windows service and inspect the executable backing the service. Service-backed requirements remain entries in the `Software` collection; there is no separate top-level `Services` collection:

```json
{
  "Name": "MySQL",
  "Service": "MySQL",
  "Version": "8.4.x",
  "Required": true,
  "MustBeRunning": true
}
```

### Explicit path

Validate software installed outside `PATH`:

```json
{
  "Name": "PHP",
  "Path": "C:\\tools\\php\\php.exe",
  "Version": "8.2.x",
  "Required": true
}
```

### Winget package

Use `PackageId` by itself when package registration is the appropriate detector:

```json
{
  "Name": "Visual C++ 2013 Redistributable x64",
  "PackageId": "Microsoft.VCRedist.2013.x64",
  "Required": true
}
```

`Command`, `Service`, and `Path` are mutually exclusive. `PackageId` may accompany any one of them as remediation metadata, or may be used by itself for package-only detection.

## Version requirements

Omit `Version` when only presence matters:

```json
{
  "Name": "Git",
  "Command": "git",
  "Required": true
}
```

Specify an exact version when every component matters:

```json
{
  "Name": "Node.js",
  "Command": "node",
  "Version": "18.20.8",
  "Required": true
}
```

Use a trailing `x` wildcard when later components are intentionally unconstrained:

```json
{
  "Name": "Node.js",
  "Command": "node",
  "Version": "18.x",
  "Required": true,
  "PackageId": "OpenJS.NodeJS.18"
}
```

| Installed | Required  | Result |
| --------- | --------- | ------ |
| `18.20.8` | `18.20.8` | PASS   |
| `18.20.8` | `18.x`    | PASS   |
| `8.4.9`   | `8.4.x`   | PASS   |
| `8.5.0`   | `8.4.x`   | FAIL   |

Without a wildcard, envcheck requires an exact component-for-component match.

## Custom version detection

Most conventional command output is handled automatically:

```text
v18.20.8
PHP 8.2.35
git version 2.51.0
go version go1.25.3 windows/amd64
```

For nonstandard output, configure `VersionArguments` and `VersionPattern`.

For example, WSL reports its default generation through `wsl --status`:

```text
Default Version: 2
```

Represent that requirement as:

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

A custom `VersionPattern` must contain a named capture group called `version`.

## Broken-installation detection

Installed does not necessarily mean usable.

Consider this state:

```text
Get-Command node
    -> not found

winget list --id OpenJS.NodeJS.18
    -> Node.js 18.20.8 installed
```

A normal bootstrap utility might attempt another installation. `envcheck` recognizes the inconsistency instead:

```text
FAIL  Node.js

Command 'node' was not found, but Winget reports the package as installed.
The installation appears incomplete or damaged.
Automatic bootstrap has been disabled.
```

This state is classified as `BrokenInstallation`, separately from genuinely missing software.

## Environment variables

Environment requirements verify that a variable contains a meaningful value, not merely that its name exists:

```json
{
  "Environment": [
    {
      "Name": "APP_ENV",
      "Required": true,
      "Secret": false
    },
    {
      "Name": "API_TOKEN",
      "Required": true,
      "Secret": true
    }
  ]
}
```

Null, empty, and whitespace-only values fail validation. Secret values are never printed:

```text
PASS  API_TOKEN    ********
```

## Required files

Files can be required as part of the environment specification:

```json
{
  "Files": [
    {
      "Name": "Application configuration",
      "Path": ".env",
      "Required": true
    },
    {
      "Name": "Composer configuration",
      "Path": "composer.json",
      "Required": true
    }
  ]
}
```

For each configured path, envcheck verifies that it:

1. exists,
2. is a file rather than a directory, and
3. is not zero bytes.

Example output:

```text
PASS  Composer configuration     composer.json (1937 bytes)
FAIL  Application configuration  File is empty: .env
```

## Connectivity checks

TCP endpoints can be included in the environment specification:

```json
{
  "Connectivity": [
    {
      "Name": "Local database",
      "Host": "localhost",
      "Port": 3306,
      "TimeoutMs": 3000,
      "Required": true
    }
  ]
}
```

Connectivity checks currently verify TCP reachability only. They do not perform protocol-level authentication or application-health checks.

## Complete example configuration

See [`envcheck.example.json`](./envcheck.example.json) for a copy-ready, generic configuration.

```json
{
  "Name": "Example Development Environment",
  "Software": [
    {
      "Name": "Git",
      "Command": "git",
      "Required": true,
      "PackageId": "Git.Git"
    },
    {
      "Name": "Node.js",
      "Command": "node",
      "Version": "18.x",
      "Required": true,
      "PackageId": "OpenJS.NodeJS.18"
    },
    {
      "Name": "WSL 2",
      "Command": "wsl",
      "VersionArguments": ["--status"],
      "VersionPattern": "Default Version:\s*(?<version>\d+)",
      "Version": "2",
      "Required": true
    },
    {
      "Name": "MySQL",
      "Service": "MySQL",
      "Version": "8.4.x",
      "Required": true,
      "MustBeRunning": true
    }
  ],
  "Environment": [
    {
      "Name": "APP_ENV",
      "Required": true,
      "Secret": false
    }
  ],
  "Files": [
    {
      "Name": "Environment configuration",
      "Path": "C:\path\to\project\.env",
      "Required": true
    }
  ],
  "Connectivity": [
    {
      "Name": "Local database",
      "Host": "localhost",
      "Port": 3306,
      "TimeoutMs": 3000,
      "Required": true
    }
  ]
}
```

## Winget bootstrap

By default, envcheck is read-only:

```powershell
.\envcheck.ps1
```

When a missing requirement has a configured `PackageId`, bootstrap mode can offer to install it:

```powershell
.\envcheck.ps1 -Bootstrap
```

Without `-Yes`, envcheck asks before each eligible installation. Winget and the underlying installer remain interactive, so any required source or package agreements are presented to the user rather than accepted automatically.

For fully approved bootstrap:

```powershell
.\envcheck.ps1 -Bootstrap -Yes
```

`-Yes` approves all eligible envcheck package installations and automatically accepts any required Winget source and package agreements. In this mode envcheck uses Winget's unattended/silent installation behavior. `-Yes` has no effect without `-Bootstrap`.

envcheck deliberately distinguishes among failure states:

| Failure kind         | Meaning                                                      | Automatic remediation |
| -------------------- | ------------------------------------------------------------ | --------------------- |
| `Missing`            | Required software cannot be found                            | May be offered        |
| `VersionMismatch`    | Software exists but does not satisfy the version requirement | No                    |
| `BrokenInstallation` | Registration exists but the usable software does not         | No                    |
| `ServiceState`       | A required service is not in the expected state              | No                    |
| `VersionDetection`   | Software exists but its version cannot be determined         | No                    |
| `Configuration`      | The envcheck requirement is invalid or ambiguous             | No                    |

The goal is safe reconciliation, not aggressive mutation of the workstation.

## Example output

```text
Development Environment
=======================
Mode: check only

Software
--------
PASS  Git                     2.51.0
PASS  Node.js                 18.20.8 (expected 18.x)
PASS  WSL 2                   2 (expected 2)
PASS  MySQL                   8.4.9 (expected 8.4.x); Service is running.

Environment
-----------
PASS  APP_ENV                 local

Files
-----
PASS  Environment configuration  .env (1240 bytes)

Connectivity
------------
PASS  Local database          localhost:3306

Summary
-------
6 passed
0 warnings
0 failed
```

## Exit codes

| Code | Meaning                              |
| ---- | ------------------------------------ |
| `0`  | All required checks passed           |
| `1`  | One or more required checks failed   |
| `2`  | envcheck itself encountered an error |

## Design principles

### Configuration describes intent

Configuration should say:

```json
{
  "Name": "Node.js",
  "Command": "node",
  "Version": "18.x",
  "Required": true
}
```

It should not require every user to describe implementation details that envcheck can reasonably own.

### Detection and remediation are separate

How software is detected is not necessarily how it is installed:

```json
{
  "Name": "Node.js",
  "Command": "node",
  "Version": "18.x",
  "PackageId": "OpenJS.NodeJS.18"
}
```

This means:

```text
Detection:
    resolve and execute node

Validation:
    installed version must satisfy 18.x

Remediation:
    use OpenJS.NodeJS.18 when genuinely missing
```

### Registration is not health

Package-manager state is evidence, not proof.

A healthy development requirement may involve checking executable existence, command execution, version, service state, file integrity, and connectivity. Package-manager registration is evidence, not proof of health.

### Prefer diagnosis over destructive repair

If envcheck cannot confidently distinguish safe remediation from potentially destructive modification, envcheck reports the problem instead of changing the machine.

## Planned capabilities

- `.env` file parsing and validation
- PHP extension validation
- PATH precedence validation
- Windows optional-feature and Docker backend validation
- Dependency relationships and ordered bootstrap
- Additional package-manager adapters

## Non-goals

`envcheck` is not intended to become:

- a general-purpose configuration-management platform,
- a replacement for Docker or dev containers,
- an endpoint-management system,
- a full package manager,
- or an excuse to automatically modify every discrepancy it finds.

The focus is the developer-workstation boundary:

> Make development-environment assumptions explicit, observable, reproducible, and safely actionable.

## Security

Configuration files may contain environment-specific metadata. Do not commit secrets.

Recommended `.gitignore` entries:

```gitignore
envcheck.json
envcheck.*.json
!envcheck.example.json
!envcheck.schema.json

.env
.env.*
!.env.example
```

Secret environment-variable values are redacted from envcheck output. Bootstrap operations are opt-in and require explicit authorization.

## Development

The current implementation targets PowerShell on Windows.

Analyze the script with PSScriptAnalyzer:

```powershell
Invoke-ScriptAnalyzer .\envcheck.ps1
```

Format it when `Invoke-Formatter` is available:

```powershell
Invoke-Formatter `
    -ScriptDefinition (Get-Content .\envcheck.ps1 -Raw) |
    Set-Content .\envcheck.ps1
```

Exercise both operating modes:

```powershell
.\envcheck.ps1
.\envcheck.ps1 -Bootstrap
.\envcheck.ps1 -Bootstrap -Yes
```

## License

A license has not yet been selected.

If this repository is released as open source, a permissive license such as Apache-2.0 or MIT is a natural fit.

## Philosophy

Developer setup documentation inevitably drifts.

Executable validation does not have to.

The objective is not to make every workstation identical. The objective is to make the assumptions required to do useful work explicit, testable, and recoverable.
