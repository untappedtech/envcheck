# envcheck Roadmap

## Guiding principle

New functionality should be driven by concrete development-environment failures and reproducibility needs, not by a desire to become a general-purpose configuration-management system.

The PowerShell implementation is a prototype for discovering the correct model. A Go rewrite should happen only after the model is stable enough to justify stronger abstractions.

## Current prototype

The current Windows PowerShell prototype supports or is intended to support:

- JSON configuration,
- JSON Schema validation,
- command-based software detection,
- explicit-path software detection,
- Windows service detection,
- Winget package detection,
- exact version requirements,
- trailing wildcard requirements such as `18.x` and `8.4.x`,
- custom version arguments,
- custom version extraction patterns,
- required and optional requirements,
- secret environment-variable redaction,
- required/nonempty file checks,
- TCP connectivity checks,
- broken-installation detection,
- conservative Winget bootstrap,
- and process exit codes suitable for automation.

## V0.1: Stabilize what exists

The immediate goal is reliability rather than breadth.

### Configuration

- Make JSON the documented primary interface.
- Keep `envcheck.example.json` synchronized with implementation behavior.
- Keep `envcheck.schema.json` synchronized with the example and implementation.
- Support `$schema` in configuration documents.
- Reject unknown properties.
- Define and document path-resolution semantics.

### Software detection

- Harden `Command` detection.
- Harden `Path` detection.
- Harden service `BinaryPathName` parsing.
- Verify `PackageId` parsing behavior across expected Winget output.
- Preserve mutual exclusivity among detection strategies.

### Version handling

- Test generic version extraction extensively.
- Test NUL-character normalization.
- Test exact matching.
- Test trailing wildcard matching.
- Validate malformed wildcard requirements.
- Validate custom `VersionPattern` requirements.
- Produce better diagnostics when a custom pattern does not capture `version`.

### Failure classification

Stabilize explicit classifications such as:

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

Avoid using message text as programmatic state.

### Remediation

- Keep validation read-only by default.
- Bootstrap only on explicit request.
- Offer normal installation only for genuinely missing software.
- Continue suppressing bootstrap for broken/inconsistent installations.
- Never derive a literal Winget `--version` from wildcard validation constraints.
- Improve Winget error reporting.

### Tests

Add automated tests covering at least:

```text
healthy installation
missing installation
wrong version
optional requirement
broken installation
version parsing failure
invalid configuration
stopped required service
missing file
zero-byte file
reachable endpoint
unreachable endpoint
```

## V0.2: Development-runtime awareness

These capabilities have concrete use cases but should follow V0.1 stabilization.

### Dotenv support

Add explicit environment sources:

```json
{
  "Name": "API_TOKEN",
  "Source": "DotEnv",
  "File": ".env",
  "Required": true,
  "Secret": true
}
```

Initial dotenv behavior should:

- ignore comments and blank lines,
- split on the first `=`,
- preserve additional `=` characters in values,
- support matching outer quotes,
- optionally accept `export `,
- treat empty values as unsatisfied requirements,
- never execute dotenv content,
- never expose secret values,
- and avoid variable interpolation initially.

### PATH precedence validation

Support requirements where an executable must not merely exist, but must be the executable selected by normal command resolution.

Example future semantics:

```json
{
  "Name": "PHP",
  "Path": "C:\\tools\\php\\php.exe",
  "Version": "8.2.x",
  "Required": true,
  "RequireOnPath": true
}
```

The exact schema is not final.

### Runtime-module validation

PHP is the first concrete use case.

Possible future configuration:

```json
{
  "Name": "PHP",
  "Path": "C:\\tools\\php\\php.exe",
  "Version": "8.2.x",
  "Modules": ["fileinfo", "sockets", "curl", "mbstring", "pdo_mysql"]
}
```

This should probably become a general capability rather than a PHP-only special case if analogous requirements emerge for other runtimes.

### Project checks

Differentiate workstation prerequisites from repository/project readiness.

Potential checks include:

```text
composer.json exists
composer.lock exists
vendor/autoload.php exists
package.json exists
package-lock.json exists
node_modules exists
.env exists and is nonempty
expected dotenv keys exist
framework CLI can boot
```

Project dependency installation should remain outside automatic workstation remediation unless there is a strong reason to combine them.

## V0.3: Windows platform capabilities

### WSL

Replace regex-based WSL detection with explicit platform semantics where practical.

Potential checks:

- WSL command exists,
- default WSL generation is 2,
- required distribution exists,
- distribution is WSL 2,
- WSL can execute a basic command successfully.

### Windows optional features

Possible capabilities:

```text
Windows Subsystem for Linux
VirtualMachinePlatform
Hyper-V related requirements when relevant
```

### Docker Desktop

Distinguish:

```text
Docker Desktop installed
docker command available
docker daemon reachable
expected backend active
```

Do not consider `docker.exe` existing equivalent to a healthy Docker environment.

## Later V0.x: Developer-tool integrity

A real workstation incident demonstrated that developer tooling can remain registered while files are missing or damaged.

Potential VS Code checks:

```text
VS Code executable exists
VS Code version
expected extension IDs
extension version
extension package directory exists
package.json exists
```

This is a legitimate future capability but should not become part of V0.1 simply because it is possible.

## Dependency relationships

Some software has prerequisites.

The initial prototype can rely on declaration order, but a future version may support explicit dependencies:

```json
{
  "Name": "Example Runtime",
  "WingetPackage": "Vendor.Runtime",
  "DependsOn": ["Visual C++ Runtime"]
}
```

If implemented, dependencies require:

- unique stable requirement identifiers,
- validation of references,
- cycle detection,
- topological ordering,
- and clear behavior when prerequisites fail.

Do not implement dependency graphs until declaration order is proven insufficient.

## Package-manager abstraction

Winget is the current Windows remediation provider, not the permanent domain model.

Potential future providers:

```text
Winget
Chocolatey
Homebrew
APT
DNF
```

The requirement model should not become polluted with Winget-specific assumptions that prevent future providers.

## Reporting

Future reporting formats may include:

```text
human-readable console output
JSON output
CI-friendly summaries
```

JSON output should expose structured failure classifications rather than requiring consumers to parse messages.

## Schema versioning

Before a public stable release, introduce explicit schema versioning.

Recommended hosted layout:

```text
/envcheck/schema.json
/envcheck/schema/v1.json
/envcheck/schema/v2.json
```

Committed configurations should reference a versioned schema URL so their semantics remain stable.

## Go rewrite

The Go rewrite should not be triggered by dissatisfaction with PowerShell syntax alone.

Start the rewrite when:

1. the configuration model is stable,
2. failure classifications are stable,
3. remediation boundaries are understood,
4. enough automated behavior exists that stronger types provide real value,
5. portability or distribution becomes materially important.

### Goals of the Go implementation

- single distributable binary,
- explicit typed requirement strategies,
- testable provider interfaces,
- structured output,
- stronger configuration validation,
- cleaner cross-platform support where appropriate,
- easier automated tests,
- and more reliable package-manager adapters.

### Non-goal of the rewrite

Do not recreate PowerShell implementation details mechanically.

The rewrite should encode the stable domain model, not preserve prototype accidents.

## Longer-term possibilities

Only pursue these if real users require them:

- environment snapshots,
- environment diffing,
- machine-to-machine comparison,
- CI validation of environment specifications,
- generated onboarding reports,
- setup-plan previews,
- dry-run remediation planning,
- extension/provider SDK,
- organization-managed schema catalogs.

## Release philosophy

A useful progression would be:

```text
v0.x
    PowerShell prototype and model discovery

v1
    stable configuration contract and dependable implementation
```

Whether v1 is PowerShell or Go should be determined by product maturity, not predetermined solely by language preference.
