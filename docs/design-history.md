# envcheck Design History

## Purpose

This document records the reasoning behind envcheck's major design decisions.

It is not an incident log and intentionally avoids organization-specific details. The goal is to preserve lessons that are useful to future maintainers without binding the project to the environment that originally exposed them.

## 1. From package presence to environment health

The earliest prototype primarily asked whether expected software was present.

That quickly proved insufficient. A developer can encounter states such as:

```text
package manager says installed
executable is missing
```

or:

```text
runtime exists
wrong runtime wins PATH resolution
```

or:

```text
service exists
service is stopped
```

The project therefore shifted from package inventory toward environment capability validation.

### Decision

Treat package-manager state as evidence, not proof of health.

Where possible, validate the capability developers actually use.

## 2. Detection strategies became explicit

Initially, software requirements naturally assumed a command such as:

```text
node --version
php --version
git --version
```

Real environments introduced software that did not fit that assumption.

Examples included:

- server software represented by a Windows service,
- bundled runtimes not intentionally placed on `PATH`,
- desktop applications and prerequisites that are best represented by package registration.

### Decision

Model executable-backed detection explicitly through:

```text
Command
Service
Path
```

and use `PackageId` for package-based detection or remediation.

`Command`, `Service`, and `Path` are mutually exclusive primary detectors.

`PackageId` intentionally behaves differently:

- By itself, it provides package-based detection and remediation.
- With `Command`, `Service`, or `Path`, the executable-backed property remains the detector and `PackageId` supplies remediation identity.

### Why this distinction?

A requirement containing both:

```json
{
  "Command": "mysqld",
  "Service": "MySQL"
}
```

is ambiguous because it specifies two primary detectors.

By contrast:

```json
{
  "Command": "git",
  "PackageId": "Git.Git"
}
```

is not ambiguous. `git` determines whether the capability works; `Git.Git` identifies how envcheck may provision it if genuinely missing.

Explicit configuration errors are preferable to implicit precedence among primary detectors.

## 3. Service-backed software

A Windows service may be the most accurate identity for server software.

The service model was added so envcheck could validate:

```text
service exists
service binary exists
binary reports acceptable version
service is running when required
```

### Decision

Resolve service executables from `BinaryPathName`, with CIM fallback where necessary.

Validate the executable and service state separately. A registered service is not by itself proof that the underlying software is usable.

Service-backed requirements belong in the top-level `Software` collection rather than a separate `Services` collection.

## 4. Explicit paths

Some toolchains bundle runtimes internally. Those runtimes can be valid project requirements without being global commands.

### Decision

Add `Path` as a first-class detection strategy rather than forcing users to modify global `PATH` merely so envcheck can find software.

This preserves the distinction between:

```text
runtime exists at expected location
```

and:

```text
runtime is the default shell command
```

That distinction led to the future PATH-precedence requirement.

## 5. Exact versions were too rigid

The first version design used exact equality:

```text
expected 8.4.9
actual 8.4.9
```

Some environments care about major/minor compatibility but not patch level.

### Decision

Support a deliberately small wildcard syntax:

```text
18.x
8.4.x
```

This handles the common case without prematurely building a full semantic-version constraint engine.

### Current semantics

```text
18.20.8 satisfies 18.x
8.4.9 satisfies 8.4.x
8.5.0 does not satisfy 8.4.x
```

A wildcard means remaining trailing components are unconstrained.

## 6. Generic parsing plus an escape hatch

Requiring every software entry to contain a regex made configuration noisy and exposed implementation details.

Most tools emit conventional dotted versions and should need no special configuration. Some tools, however, expose the relevant value through unusual status output.

### Decision

Use generic parsing by default and provide optional overrides:

```text
VersionArguments
VersionPattern
```

`VersionArguments` defaults to `--version` for executable-backed detection.

`VersionPattern` must expose a named capture called `version`.

This keeps ordinary configuration simple while retaining an escape hatch for unusual tools.

A plain `Version` is also valid for package-only requirements because Winget can report an installed package version. `VersionArguments` and `VersionPattern` require executable-backed detection.

## 7. Native output normalization belongs in the engine

Some Windows commands can emit output containing embedded NUL characters when captured programmatically even though console display appears normal.

Making every configuration regex account for encoding artifacts would be the wrong abstraction.

### Decision

Normalize native output in envcheck before applying version extraction.

Configuration describes meaningful output, not capture-encoding quirks.

## 8. BrokenInstallation became a distinct state

A particularly important real-world failure occurred when package registration survived but a primary executable did not.

A naive bootstrap flow would see:

```text
command missing
```

and attempt another package installation.

But if the package manager simultaneously says:

```text
package installed
```

then the environment is not simply missing software. It is inconsistent.

### Decision

Introduce `BrokenInstallation`.

Conceptually:

```text
command missing
      |
      v
package manager says not installed
      |
      v
Missing
```

versus:

```text
command missing
      |
      v
package manager says installed
      |
      v
BrokenInstallation
```

### Safety consequence

`Missing` may be eligible for bootstrap.

`BrokenInstallation` is diagnostic only.

This distinction is a core project feature and should not be removed merely to simplify implementation.

## 9. Validation version is not installer version

An early bootstrap design attempted to pass the configured validation version directly to Winget.

This breaks for constraints such as:

```text
18.x
```

and conflates validation with provisioning.

### Decision

Keep these concepts separate:

```text
Version
    what installed software must satisfy

PackageId
    what package family is used for package detection or provisioning
```

For example:

```json
{
  "Name": "Node.js",
  "Command": "node",
  "Version": "18.x",
  "PackageId": "OpenJS.NodeJS.18"
}
```

The package family selects Node 18. envcheck independently validates that the resulting installed version satisfies `18.x`.

## 10. Winget-specific identity names were unnecessary

An intermediate configuration model used separate Winget-specific properties for package detection and remediation.

That created two identifiers even though both values represented the same underlying package identity, and it leaked the current package-manager implementation into the public schema.

### Decision

Collapse the public configuration to one flat property:

```text
PackageId
```

For PowerShell V0.x, `PackageId` is interpreted through Winget.

A nested or per-platform package model may make sense later when a cross-platform implementation genuinely supports multiple package managers. That complexity does not belong in the Windows-only prototype.

## 11. Generic remediation first, package exceptions second

It is tempting to encode full installation command lines in configuration.

That would make envcheck configuration procedural rather than declarative.

### Decision

Generate a sensible generic Winget installation command from `PackageId`.

Only add installation overrides when a real package demonstrably requires them.

The project should resist becoming a collection of handwritten installation scripts.

## 12. Consent and package agreements are different decisions

Bootstrap initially treated package installation consent and automatic agreement acceptance too similarly.

A user saying yes to one interactive installation does not imply blanket authorization for envcheck to accept all package or source agreements on the user's behalf.

### Decision

Keep two clear operating modes.

Interactive bootstrap:

```powershell
.\envcheck.ps1 -Bootstrap
```

- envcheck asks before each eligible package installation,
- Winget remains interactive,
- required source and package agreements are presented to the user,
- envcheck does not automatically accept those agreements.

Fully approved bootstrap:

```powershell
.\envcheck.ps1 -Bootstrap -Yes
```

- all eligible installations are approved,
- required Winget source and package agreements may be accepted automatically,
- installation may run unattended/silent.

A separate noninteractive mode was removed because it did not provide a sufficiently distinct or intuitive contract.

## 13. File existence was not enough

A zero-byte configuration file usually does not satisfy a development requirement even though the filesystem path exists.

### Decision

File checks verify:

```text
exists
is a file
length > 0
```

An `AllowEmpty` option can be added later if a concrete requirement emerges.

## 14. Environment variables need values

A variable name can technically exist while containing no useful value.

### Decision

Treat null, empty, and whitespace-only values as unsatisfied.

Secrets are checked but never displayed.

## 15. External JSON became the preferred interface

The prototype originally relied heavily on an embedded PowerShell hashtable.

That is convenient for implementation but poor as the public contract because it couples the environment definition to the script.

### Decision

Prefer:

```text
envcheck.ps1
    engine

envcheck.json
    environment specification
```

Examples and public documentation should use JSON.

Embedded configuration remains a fallback and development convenience.

## 16. JSON Schema became part of the product

Once JSON became the preferred configuration format, typos and discoverability became important.

### Decision

Provide `envcheck.schema.json` using JSON Schema Draft 2020-12.

Use `additionalProperties: false` so mistakes such as:

```json
{
  "Requred": true
}
```

produce editor errors rather than silently being ignored.

The schema is documentation, editor tooling, and an executable configuration contract.

The schema uses:

- `description` for portable user-facing help,
- `examples` for representative values,
- `markdownDescription` selectively for richer editor help,
- `$comment` for maintainer-facing design notes.

Schema changes should remain synchronized with the script, example configuration, README, and architecture documentation.

## 17. Product-scoped schema hosting

If schemas are hosted publicly, paths should be organized around products rather than artifact types.

Preferred:

```text
/envcheck/schema/v1.json
/flowtrace/schema/v1.json
```

rather than:

```text
/schema/envcheck.schema.json
/schema/flowtrace.schema.json
```

### Reason

Product-scoped namespaces leave room for documentation, releases, and related artifacts without turning a global `/schema` directory into a miscellaneous registry.

Committed configurations should prefer versioned schema URLs once those schemas are actually published.

## 18. PATH precedence is a distinct future concern

An expected executable can exist at the correct path while another installation is selected by normal shell resolution.

This matters for tools with configuration coupled to installation location, such as PHP and its `php.ini`.

### Decision

Do not pretend a `Path` check proves normal command resolution.

Add a future PATH-precedence capability instead of overloading the meaning of `Path`.

## 19. Runtime version is not complete project readiness

A runtime can have the correct version while missing required modules or extensions.

PHP exposed this concretely through required extensions such as `fileinfo` and `sockets`.

### Decision

Treat runtime-module checking as a future capability.

Avoid adding one-off PHP-specific code until the general shape is understood.

## 20. Workstation requirements and project requirements differ

A workstation should provide runtimes and tooling.

An application repository should define its framework and package dependencies through its own lock files.

### Decision

Do not model frameworks such as Laravel as globally installed workstation software merely because a project uses them.

Potential future project checks should be a separate layer.

## 21. WSL exposed platform capabilities

`wsl.exe` existing does not prove that the machine has a useful WSL 2 environment.

Similarly, `docker.exe` existing does not prove the Docker daemon or required backend works.

### Decision

The current prototype may use command/status checks, but the long-term model should include explicit platform capabilities for things such as:

```text
WSL 2
Windows optional features
virtualization
Docker backend
```

## 22. The PowerShell prototype is intentional

PowerShell is not viewed as the permanent architecture simply because it is the current implementation.

### Decision

Use PowerShell while the domain is changing rapidly.

Move to Go when stable concepts justify:

- stronger types,
- easier automated testing,
- provider interfaces,
- distribution as a single binary,
- structured output,
- broader portability.

Do not rewrite merely because PowerShell syntax becomes inconvenient.

## 23. Features should earn their complexity

Several possible features have been deliberately deferred:

```text
full dependency graphs
semver range expressions
automatic damaged-install repair
multiple package managers
VS Code extension integrity
Docker platform introspection
project dependency installation
```

### Decision

Add capabilities when a concrete environment need proves their value.

This keeps the product aligned with its original purpose: practical, predictable environment validation rather than speculative platform construction.

## Summary of durable decisions

The following decisions should be considered foundational unless new evidence disproves them:

1. JSON is the preferred public configuration interface.
2. Configuration describes intent rather than implementation plumbing.
3. Detection, validation, and remediation remain separate.
4. `Command`, `Service`, and `Path` are mutually exclusive primary detectors.
5. `PackageId` alone provides package detection and remediation; with a primary detector it provides remediation metadata.
6. Generic version parsing is the default.
7. `VersionPattern` is an escape hatch.
8. Exact and simple trailing-wildcard version requirements are enough for the current stage.
9. Package registration is not proof of health.
10. Broken installations are not ordinary missing installations.
11. Automatic remediation remains conservative.
12. Interactive bootstrap does not auto-accept package agreements; `-Yes` explicitly authorizes agreement acceptance.
13. Schema validation should be strict and useful as editor documentation.
14. Workstation requirements and project dependencies are separate concepts.
15. The PowerShell prototype discovers the model before the Go implementation freezes it.
16. New complexity must be justified by a real requirement.
