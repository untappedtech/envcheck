# Contributing to envcheck

Thanks for your interest in envcheck.

The project is currently an early PowerShell prototype, so contributions should prioritize clarity, safety, and stabilization of the configuration model over rapid feature expansion.

## Development principles

### Keep configuration declarative

Prefer configuration that describes the desired environment:

```json
{
  "Name": "Node.js",
  "Command": "node",
  "Version": "18.x",
  "Required": true,
  "WingetId": "OpenJS.NodeJS.18"
}
```

over configuration containing arbitrary installation scripts or implementation logic.

### Prefer diagnosis over destructive remediation

A failed requirement should not automatically imply that envcheck should change the machine.

Automatic remediation should be limited to cases where the state and corrective action are well understood.

### Preserve failure semantics

Do not collapse materially different states into a generic failure when the distinction affects diagnosis or remediation.

Examples include:

```text
Missing
VersionMismatch
BrokenInstallation
VersionDetection
ServiceState
Configuration
```

### Avoid speculative features

New requirements should ideally be motivated by a concrete development-environment problem.

If a feature adds substantial configuration or abstraction, explain the actual use case it solves.

## Repository files

The important public artifacts are:

```text
envcheck.ps1
envcheck.example.json
envcheck.schema.json
README.md
docs/
```

Environment-specific configuration should not be committed.

## Configuration changes

When changing the configuration model, update all of the following in the same change:

1. `envcheck.ps1`
2. `envcheck.schema.json`
3. `envcheck.example.json`
4. `README.md`
5. relevant documentation under `docs/`
6. relevant tests

Do not allow the schema, examples, and implementation to drift apart.

## PowerShell style

Prefer readable, conventional PowerShell over compressed expressions.

Good:

```powershell
if ($required) {
    $status = 'FAIL'
}
else {
    $status = 'WARN'
}
```

Avoid packing control flow and declarations onto a single line.

Use descriptive variable and function names.

Use named parameters at important call sites, particularly when arguments have similar types.

## Formatting

When available, use PSScriptAnalyzer's formatter:

```powershell
Invoke-Formatter `
    -ScriptDefinition (Get-Content .\envcheck.ps1 -Raw) |
    Set-Content .\envcheck.ps1
```

Analyze changes with:

```powershell
Invoke-ScriptAnalyzer .\envcheck.ps1
```

## JSON formatting

JSON examples should be valid JSON and formatted consistently.

The repository schema should validate the example file.

When editing in VS Code, associate the configuration with the repository schema:

```json
{
  "$schema": "./envcheck.schema.json"
}
```

## Tests

Changes to requirement behavior should cover the important states for that requirement.

At minimum, consider:

```text
healthy
missing
optional missing
invalid configuration
wrong version
version cannot be detected
broken/inconsistent state
```

Version tests should include exact and wildcard requirements.

## Safety-sensitive changes

Remediation changes deserve extra scrutiny.

Before adding an automatic corrective action, answer:

1. Can the observed state be identified reliably?
2. Is the remedial action deterministic?
3. Can the action damage an existing usable installation?
4. Can the action silently change major versions or runtime behavior?
5. Is user consent required?
6. Is reporting the problem safer than changing it?

When uncertain, choose reporting.

## Commit messages

Conventional-style commit messages are encouraged.

Examples:

```text
feat: add service-backed software detection
feat: detect inconsistent software installations
feat: support custom version detection patterns
fix: preserve optional requirement warning status
refactor: isolate version matching logic
docs: document JSON configuration schema
```

## Pull requests

A useful pull request should explain:

- the concrete problem,
- the previous behavior,
- the new behavior,
- configuration changes,
- safety implications,
- tests performed,
- and any remaining limitations.

## Security and private information

Do not include:

- credentials,
- tokens,
- private keys,
- internal hostnames,
- client names,
- proprietary configuration,
- or private infrastructure details.

Use synthetic examples in tests and documentation.

## Future implementation work

A future Go implementation is expected, but contributions should not prematurely redesign the project around a hypothetical rewrite.

The PowerShell prototype remains the place to stabilize behavior until the domain model is mature enough for stronger types and provider interfaces.
