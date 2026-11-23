<#
.SYNOPSIS
Exports or imports Visual Studio Code extensions.

.DESCRIPTION
VSCodeExtensions.ps1 provides a simple way to back up and restore the
Visual Studio Code extensions installed for the current user.

Export records extension identifiers and their installed versions using:

    code --list-extensions --show-versions

Import reads that manifest and installs each extension using the VS Code CLI.

By default, Import preserves the exact versions recorded in the manifest.
Use -Latest to ignore recorded versions and install the latest available
version of each extension instead.

The manifest is a plain-text file with one extension per line:

    publisher.extension@version

For example:

    golang.go@0.58.0
    ms-vscode.powershell@2025.4.0
    redhat.vscode-yaml@2.0.0

Blank lines and lines beginning with # are ignored during import.

This makes the manifest suitable for source control and workstation
bootstrap/recovery workflows.

.PARAMETER Action
Specifies the operation to perform.

Valid values:

    Export
        Writes the currently installed VS Code extensions and their versions
        to the manifest specified by -Path.

    Import
        Installs extensions listed in the manifest specified by -Path.

.PARAMETER Path
Path to the extension manifest.

The default is:

    .\vscode-extensions.txt

During Export, this file is created or replaced.

During Import, this file must already exist.

.PARAMETER Latest
Applies only to Import.

Ignores versions recorded in the manifest and installs the latest available
version of each extension.

For example:

    golang.go@0.58.0

is installed as:

    golang.go

Without -Latest, the recorded version is requested.

.EXAMPLE
.\VSCodeExtensions.ps1 Export

Exports the currently installed extensions to:

    .\vscode-extensions.txt

.EXAMPLE
.\VSCodeExtensions.ps1 Export -Path .\config\vscode-extensions.txt

Exports the installed extensions to a manifest suitable for committing
with a project or workstation configuration repository.

.EXAMPLE
.\VSCodeExtensions.ps1 Import -Path .\config\vscode-extensions.txt

Installs the exact extension versions recorded in the manifest.

.EXAMPLE
.\VSCodeExtensions.ps1 Import -Path .\config\vscode-extensions.txt -Latest

Installs the extensions from the manifest, but uses the latest available
version of each extension instead of the recorded version.

.EXAMPLE
Get-Help .\VSCodeExtensions.ps1 -Full

Displays complete help for this script.

.NOTES
Requirements:

    - Visual Studio Code must be installed.
    - The VS Code CLI command "code" must be available in PATH.
    - Import requires access to the VS Code Marketplace or other configured
      extension source.

The manifest intentionally contains only extension identifiers and versions.
VS Code extension binaries are treated as disposable installation artifacts.

For reproducible development environments, consider storing the manifest in
source control alongside workstation/bootstrap configuration.

Import uses --force so an already-installed extension can be repaired or
reinstalled. This is useful when an extension directory has become incomplete
or corrupted.

Import continues after an individual extension failure and reports all failed
extensions when processing completes.

.LINK
https://code.visualstudio.com/docs/editor/command-line
#>

[CmdletBinding()]
param(
    [Parameter(
        Mandatory = $true,
        Position = 0,
        HelpMessage = 'Choose Export or Import.'
    )]
    [ValidateSet('Export', 'Import')]
    [string]$Action,

    [Parameter(
        Position = 1,
        HelpMessage = 'Path to the VS Code extension manifest.'
    )]
    [string]$Path = '.\vscode-extensions.txt',

    [Parameter(
        HelpMessage = 'Install the latest extension versions instead of versions recorded in the manifest.'
    )]
    [switch]$Latest
)

$ErrorActionPreference = 'Stop'

function Get-CodeCommand {
    <#
    .SYNOPSIS
    Locates the Visual Studio Code command-line executable.

    .DESCRIPTION
    Resolves the `code` command using PowerShell's command-discovery
    mechanism and returns the executable path used for subsequent
    Visual Studio Code CLI operations.

    This function centralizes VS Code CLI discovery so export and import
    operations fail consistently when Visual Studio Code is unavailable
    or its CLI has not been added to PATH.

    .OUTPUTS
    System.String

    Returns the resolved path to the Visual Studio Code CLI executable.

    .EXAMPLE
    $code = Get-CodeCommand

    Resolves the VS Code CLI and stores its executable path in $code.

    .NOTES
    Throws if the `code` command cannot be resolved.

    The caller should use the returned path rather than invoking `code`
    directly. This ensures all operations in the script use the same
    resolved executable.
    #>

    $command = Get-Command 'code' -ErrorAction SilentlyContinue

    if (-not $command) {
        throw @"
Visual Studio Code CLI ('code') was not found in PATH.

Open Visual Studio Code and ensure its command-line interface is available,
then start a new PowerShell session and try again.
"@
    }

    return $command.Source
}


function Export-VSCodeExtensions {
    <#
    .SYNOPSIS
    Exports installed Visual Studio Code extensions to a manifest.

    .DESCRIPTION
    Queries Visual Studio Code for the extensions installed for the
    current user and writes their identifiers and versions to a
    deterministic plain-text manifest.

    The generated format is:

        publisher.extension@version

    For example:

        golang.go@0.58.0
        ms-vscode.powershell@2025.4.0

    Entries are trimmed, sorted, and deduplicated before being written.

    The manifest can be committed to source control, copied to another
    workstation, or used as input to Import-VSCodeExtensions.

    If the parent directory of ManifestPath does not exist, the function
    creates it automatically.

    .PARAMETER Code
    Path to the Visual Studio Code command-line executable.

    Normally this value should come from Get-CodeCommand rather than
    being supplied manually.

    .PARAMETER ManifestPath
    Destination path for the extension manifest.

    If the file already exists, its contents are replaced.

    Parent directories are created automatically when necessary.

    .INPUTS
    None.

    This function does not accept pipeline input.

    .OUTPUTS
    None.

    The function writes status information to the host and creates or
    replaces the manifest file specified by ManifestPath.

    .EXAMPLE
    $code = Get-CodeCommand

    Export-VSCodeExtensions `
        -Code $code `
        -ManifestPath '.\vscode-extensions.txt'

    Exports the current VS Code extensions and their exact versions.

    .EXAMPLE
    Export-VSCodeExtensions `
        -Code (Get-CodeCommand) `
        -ManifestPath '.\config\vscode-extensions.txt'

    Exports the manifest to a project configuration directory.

    .NOTES
    The function invokes:

        code --list-extensions --show-versions

    A nonzero VS Code CLI exit code is treated as an error.

    An empty extension list is permitted but generates a warning.

    The generated manifest represents desired extension state. It does
    not back up extension binaries, settings, workspace state, or VS Code
    user configuration.
    #>

    param(
        [Parameter(Mandatory)]
        [string]$Code,

        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    Write-Host 'Exporting VS Code extensions...'

    $extensions = @(
        & $Code --list-extensions --show-versions
    )

    if ($LASTEXITCODE -ne 0) {
        throw 'VS Code failed to enumerate installed extensions.'
    }

    $extensions = @(
        $extensions |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ } |
            Sort-Object -Unique
    )

    if ($extensions.Count -eq 0) {
        Write-Warning 'VS Code reported no installed extensions.'
    }

    $parent = Split-Path -Parent $ManifestPath

    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item `
            -ItemType Directory `
            -Path $parent `
            -Force |
            Out-Null
    }

    $extensions |
        Set-Content `
            -LiteralPath $ManifestPath `
            -Encoding utf8

    Write-Host ''
    Write-Host "Exported $($extensions.Count) extension(s)."
    Write-Host "Manifest: $ManifestPath"
}


function Import-VSCodeExtensions {
    <#
    .SYNOPSIS
    Installs Visual Studio Code extensions from a manifest.

    .DESCRIPTION
    Reads a plain-text Visual Studio Code extension manifest and installs
    each listed extension using the VS Code command-line interface.

    By default, version-qualified entries are installed exactly as
    recorded:

        golang.go@0.58.0

    When UseLatest is specified, the trailing version is removed before
    installation:

        golang.go

    This allows the same manifest to support both reproducible restores
    and intentional upgrades.

    Blank lines and lines beginning with `#` are ignored.

    Each extension is installed independently. A failed extension does
    not prevent the remaining extensions from being attempted.

    At completion, all failed extension identifiers are reported
    together.

    .PARAMETER Code
    Path to the Visual Studio Code command-line executable.

    Normally this value should come from Get-CodeCommand.

    .PARAMETER ManifestPath
    Path to a text file containing one Visual Studio Code extension per
    line.

    Supported entries normally use:

        publisher.extension@version

    Comment lines beginning with `#` and blank lines are ignored.

    .PARAMETER UseLatest
    Ignores versions recorded in the manifest.

    When specified, an entry such as:

        golang.go@0.58.0

    is converted to:

        golang.go

    before being passed to the VS Code CLI.

    .INPUTS
    None.

    This function does not accept pipeline input.

    .OUTPUTS
    None.

    Progress and failure information are written to the host.

    .EXAMPLE
    Import-VSCodeExtensions `
        -Code (Get-CodeCommand) `
        -ManifestPath '.\vscode-extensions.txt'

    Reinstalls the exact extension versions recorded in the manifest.

    .EXAMPLE
    Import-VSCodeExtensions `
        -Code (Get-CodeCommand) `
        -ManifestPath '.\vscode-extensions.txt' `
        -UseLatest

    Installs the current Marketplace version of every extension listed
    in the manifest.

    .NOTES
    Extensions are installed using:

        code --install-extension <extension> --force

    The --force option is intentional. This utility is designed not only
    for workstation bootstrap but also for repair scenarios where VS Code
    believes an extension is installed even though its on-disk payload is
    incomplete or corrupt.

    If one extension fails, processing continues so a single unavailable
    Marketplace package does not prevent recovery of unrelated
    extensions.

    The function exits with code 1 if one or more installations fail.

    The function does not modify VS Code settings, keybindings, snippets,
    profiles, or workspace configuration.
    #>

    param(
        [Parameter(Mandatory)]
        [string]$Code,

        [Parameter(Mandatory)]
        [string]$ManifestPath,

        [switch]$UseLatest
    )

    if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
        throw "Extension manifest not found: $ManifestPath"
    }

    $extensions = @(
        Get-Content -LiteralPath $ManifestPath |
            ForEach-Object { $_.Trim() } |
            Where-Object {
                $_ -and
                -not $_.StartsWith('#')
            }
    )

    if ($extensions.Count -eq 0) {
        throw "Extension manifest contains no extensions: $ManifestPath"
    }

    Write-Host "Importing $($extensions.Count) VS Code extension(s)..."
    Write-Host ''

    $failed = [System.Collections.Generic.List[string]]::new()

    foreach ($extension in $extensions) {
        if ($UseLatest) {
            # Strip only the trailing @version component. Extension IDs
            # themselves retain their publisher.extension form.
            $extensionToInstall =
                $extension -replace '@[^@]+$', ''
        }
        else {
            $extensionToInstall = $extension
        }

        Write-Host "Installing $extensionToInstall ..."

        & $Code `
            --install-extension $extensionToInstall `
            --force

        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to install: $extensionToInstall"
            $failed.Add($extensionToInstall)
        }
    }

    Write-Host ''

    if ($failed.Count -gt 0) {
        Write-Warning "Import completed with $($failed.Count) failure(s)."

        foreach ($extension in $failed) {
            Write-Host "  FAILED  $extension"
        }

        exit 1
    }

    Write-Host "All $($extensions.Count) extension(s) installed successfully."
}