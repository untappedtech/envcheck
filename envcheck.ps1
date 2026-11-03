<#
.SYNOPSIS
    Checks whether the current machine satisfies a project's development
    environment requirements.

.DESCRIPTION
    envcheck validates:

      - Installed software
      - Software versions
      - Environment variables
      - Required files
      - TCP connectivity

    By default, envcheck is read-only.

    When -Bootstrap is specified, missing software with a configured Winget
    package can optionally be installed.

    Version mismatches are reported but are NOT automatically remediated in
    V0.1.

.PARAMETER Config
    Optional path to an envcheck JSON configuration file.

    If omitted, envcheck looks for:

        .\envcheck.json

    If that file does not exist, the embedded configuration is used.

.PARAMETER Bootstrap
    Enables optional Winget remediation for missing software.

    This does not automatically install anything. Each installation is
    prompted unless -Yes is also specified.

.PARAMETER Yes
    Automatically accepts configured Winget installations.

    Has no effect unless -Bootstrap is also specified.

.PARAMETER NonInteractive
    Prevents envcheck from prompting for input.

    When combined with -Bootstrap without -Yes, installations are skipped.

.EXAMPLE
    .\envcheck.ps1

.EXAMPLE
    .\envcheck.ps1 -Config .\envcheck.json

.EXAMPLE
    .\envcheck.ps1 -Bootstrap

.EXAMPLE
    .\envcheck.ps1 -Bootstrap -Yes

.EXAMPLE
    .\envcheck.ps1 -Bootstrap -NonInteractive -Yes
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Config,
    [switch]$Bootstrap,
    [switch]$Yes,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


# ============================================================================
# Embedded configuration
# ============================================================================

$EmbeddedConfig = @{
    Name = 'PIP Development Environment'

    Software = @(
        # --------------------------------------------------------------------
        # WAMP prerequisites
        # --------------------------------------------------------------------

        @{
            Name          = 'Visual C++ 2010 Redistributable x86'
            WingetPackage = 'Microsoft.VCRedist.2010.x86'
            Required      = $true
        },

        @{
            Name          = 'Visual C++ 2010 Redistributable x64'
            WingetPackage = 'Microsoft.VCRedist.2010.x64'
            Required      = $true
        },

        @{
            Name          = 'Visual C++ 2012 Redistributable x64'
            WingetPackage = 'Microsoft.VCRedist.2012.x64'
            Required      = $true
        },

        @{
            Name          = 'Visual C++ 2012 Redistributable x86'
            WingetPackage = 'Microsoft.VCRedist.2012.x86'
            Required      = $true
        },

        @{
            Name          = 'Visual C++ 2013 Redistributable x64'
            WingetPackage = 'Microsoft.VCRedist.2013.x64'
            Required      = $true
        },

        @{
            Name          = 'Visual C++ 2013 Redistributable x86'
            WingetPackage = 'Microsoft.VCRedist.2013.x86'
            Required      = $true
        },

        @{
            Name          = 'Visual C++ 2014 Redistributable x64'
            WingetPackage = 'Microsoft.VCRedist.2015+.x64'
            Required      = $true
        },

        @{
            Name          = 'Visual C++ 2014 Redistributable x86'
            WingetPackage = 'Microsoft.VCRedist.2015+.x86'
            Required      = $true
        },

        @{
            Name          = 'WAMP Server Package'
            WingetPackage = 'Wampserver.Wampserver'
            Required      = $true
        },

        @{
            Name          = 'VS Code'
            WingetPackage = 'Microsoft.VisualStudioCode'
            Required      = $true
        },


        # --------------------------------------------------------------------
        # Development tools / runtimes
        # --------------------------------------------------------------------

        @{
            Name     = 'Docker'
            Command  = 'docker'
            Required = $true
            WingetId = 'Docker.DockerDesktop'
        },

        @{
            Name     = 'Git'
            Command  = 'git'
            Required = $true
            WingetId = 'Git.Git'
        },

        @{
            Name     = 'Node.js'
            Command  = 'node'
            Version  = '18.20.8'
            Required = $true
            WingetId = 'OpenJS.NodeJS.18'
            Source   = 'winget'
        },

        @{
            Name     = 'PHP'
            Command  = 'php'
            Version  = '8.2.35'
            Required = $true
        },


        # --------------------------------------------------------------------
        # Services
        # --------------------------------------------------------------------

        @{
            Name          = 'MySQL'
            Service       = 'MySQL64'
            Version       = '8.4.x'
            Required      = $true
            MustBeRunning = $true
        }
    )


    # ------------------------------------------------------------------------
    # Environment variables
    #
    # V0.1 checks the environment visible to the current PowerShell process.
    #
    # Secret = $true means envcheck reports whether the value exists but
    # never displays the value itself.
    # ------------------------------------------------------------------------

    Environment = @(
        # Enable these once we know exactly which variables the development
        # environment requires.
        #
        # @{
        #     Name     = 'APP_ENV'
        #     Required = $true
        #     Secret   = $false
        # },
        #
        # @{
        #     Name     = 'PIM_API_URL'
        #     Required = $true
        #     Secret   = $false
        # },
        #
        # @{
        #     Name     = 'PIM_TOKEN'
        #     Required = $true
        #     Secret   = $true
        # }
    )


    # ------------------------------------------------------------------------
    # Required files
    #
    # Paths are currently resolved relative to the directory from which
    # envcheck is executed.
    # ------------------------------------------------------------------------

    Files = @(
        # I would leave these disabled until we're running envcheck from the
        # actual application repository. Otherwise they describe assumptions
        # we're not ready to make.
        #
        # @{
        #     Name     = '.env'
        #     Path     = '.env'
        #     Required = $true
        # },
        #
        # @{
        #     Name     = 'composer.json'
        #     Path     = 'composer.json'
        #     Required = $true
        # }
    )


    # ------------------------------------------------------------------------
    # Network connectivity
    #
    # V0.1 connectivity checks establish whether a TCP connection can be made.
    # They do not perform protocol-level or authentication checks.
    # ------------------------------------------------------------------------

    Connectivity = @(
        # Example once we know the actual requirement:
        #
        @{
            Name      = 'Local MySQL'
            Host      = 'localhost'
            Port      = 3306
            TimeoutMs = 3000
            Required  = $true
        }
    )
}


# ============================================================================
# Runtime state
# ============================================================================

$script:Results = [System.Collections.Generic.List[object]]::new()


# ============================================================================
# General helpers
# ============================================================================

<#
.SYNOPSIS
    Retrieves a named value from an envcheck configuration object.

.DESCRIPTION
    Provides uniform access to configuration values regardless of whether the
    configuration came from the embedded PowerShell hashtable or an external
    JSON file converted to a PSCustomObject.

    Returns the supplied default value when the object, property, or value
    does not exist.
#>
function Get-ConfigValue {
    param(
        [Parameter(Mandatory)]
        [object]$Object,

        [Parameter(Mandatory)]
        [string]$Name,

        [object]$Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    # Embedded configuration uses PowerShell hashtables.
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) {
            return $Object[$Name]
        }

        return $Default
    }

    # JSON configuration is converted into PSCustomObject instances.
    $property = $Object.PSObject.Properties[$Name]

    if ($null -eq $property) {
        return $Default
    }

    if ($null -eq $property.Value) {
        return $Default
    }

    return $property.Value
}


<#
.SYNOPSIS
    Writes a formatted section heading to the console.

.DESCRIPTION
    Provides consistent visual separation between envcheck output sections
    such as Software, Environment, Files, Connectivity, Bootstrap, and Summary.
#>
function Write-Section {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    Write-Host ''
    Write-Host $Name -ForegroundColor Cyan
    Write-Host ('-' * $Name.Length) -ForegroundColor Cyan
}


<#
.SYNOPSIS
    Records and displays the result of an envcheck validation.

.DESCRIPTION
    Creates a normalized result object, adds it to the script-wide Results
    collection, and writes the result to the console using a color appropriate
    for PASS, WARN, or FAIL.

    Result metadata is also retained for later summary reporting and optional
    Winget remediation.
#>
function Add-CheckResult {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('PASS', 'WARN', 'FAIL')]
        [string]$Status,

        [Parameter(Mandatory)]
        [string]$Category,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Message,

        [bool]$Required = $true,

        [string]$WingetId = '',

        [string]$WingetSource = 'winget',

        [string]$ExpectedVersion = '',

        [string]$FailureKind = ''
    )

    $result = [pscustomobject]@{
        Status          = $Status
        Category        = $Category
        Name            = $Name
        Message         = $Message
        Required        = $Required
        WingetId        = $WingetId
        WingetSource    = $WingetSource
        ExpectedVersion = $ExpectedVersion
        FailureKind     = $FailureKind
    }

    $script:Results.Add($result)

    $color = switch ($Status) {
        'PASS' {
            'Green'
        }

        'WARN' {
            'Yellow'
        }

        'FAIL' {
            'Red'
        }
    }

    Write-Host (
        '{0,-5} {1,-22} {2}' -f
        $Status,
        $Name,
        $Message
    ) -ForegroundColor $color
}


# ============================================================================
# Configuration loading
# ============================================================================

<#
.SYNOPSIS
    Loads the configuration used by envcheck.

.DESCRIPTION
    Uses the explicitly supplied -Config file when present. Otherwise looks
    for .\envcheck.json in the current directory.

    If neither exists, returns the embedded configuration defined in the
    script.

    External configuration files are expected to contain valid JSON.
#>
function Get-EnvCheckConfig {
    $configPath = $null

    if (-not [string]::IsNullOrWhiteSpace($Config)) {
        $configPath = $Config
    }
    elseif (Test-Path -LiteralPath '.\envcheck.json' -PathType Leaf) {
        $configPath = '.\envcheck.json'
    }

    if ($null -eq $configPath) {
        return [pscustomobject]$EmbeddedConfig
    }

    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "Configuration file not found: $configPath"
    }

    try {
        $json = Get-Content `
            -LiteralPath $configPath `
            -Raw

        return $json | ConvertFrom-Json
    }
    catch {
        throw "Could not load configuration '$configPath': $($_.Exception.Message)"
    }
}


# ============================================================================
# Version detection
# ============================================================================

<#
.SYNOPSIS
    Extracts a normalized numeric version from command output.

.DESCRIPTION
    Searches arbitrary version output for a conventional dotted numeric
    version.

    Prefers three- or four-component versions such as 8.4.7 or 1.2.3.4,
    falling back to two-component versions such as 8.4 when necessary.

    Common prefixes such as "v" and "go" are excluded from the returned value.
#>
function Get-NormalizedVersion {
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    if ($null -eq $Text -or $Text.Length -eq 0) {
        return $null
    }

    # Prefer a 3- or 4-component version first.
    #
    # Examples:
    #   8.4.7
    #   18.20.8
    #   1.2.3.4
    #
    # Optional prefixes such as "v" and "go" are ignored.
    $detailedPattern = '(?<!\d)(?:v|go)?(?<version>\d+\.\d+\.\d+(?:\.\d+)?)(?!\d)'

    $match = [regex]::Match(
        $Text,
        $detailedPattern,
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($match.Success) {
        return $match.Groups['version'].Value
    }

    # Fall back to a 2-component version only if no more specific version
    # was found.
    #
    # Examples:
    #   8.4
    #   3.12
    $shortPattern = '(?<!\d)(?:v|go)?(?<version>\d+\.\d+)(?!\.\d)(?!\d)'

    $match = [regex]::Match(
        $Text,
        $shortPattern,
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($match.Success) {
        return $match.Groups['version'].Value
    }

    return $null
}


<#
.SYNOPSIS
    Executes a program and determines its installed version.

.DESCRIPTION
    Runs the supplied executable using its configured version arguments,
    defaulting to --version, and passes the resulting output through
    Get-NormalizedVersion.

    Returns a structured result containing the detected version, original
    command output, and success state.
#>
function Get-InstalledVersion {

    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [object[]]$Arguments = @('--version')
    )

    try {
        $output = (
            & $Command @Arguments 2>&1 |
            Out-String
        ).Trim()

        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{
                Success = $false
                Version = $null
                Output  = $output
            }
        }

        $version = Get-NormalizedVersion -Text $output

        if ($null -eq $version) {
            return [pscustomobject]@{
                Success = $false
                Version = $null
                Output  = $output
            }
        }

        return [pscustomobject]@{
            Success = $true
            Version = $version
            Output  = $output
        }
    }
    catch {
        return [pscustomobject]@{
            Success = $false
            Version = $null
            Output  = $_.Exception.Message
        }
    }
}


<#
.SYNOPSIS
    Determines whether an installed version satisfies a configured version.

.DESCRIPTION
    Compares dotted numeric versions component by component.

    Supports trailing "x" wildcards for intentionally unconstrained version
    components. For example:

        8.4.7 matches 8.4.x
        8.4.12 matches 8.4.x
        8.5.0 does not match 8.4.x
        18.20.8 matches 18.x

    Without a wildcard, an exact component-for-component match is required.
#>
function Test-VersionMatch {
    param(
        [Parameter(Mandatory)]
        [string]$Actual,

        [Parameter(Mandatory)]
        [string]$Expected
    )

    if ($Expected.Length -eq 0) {
        return $true
    }

    $actualParts = $Actual.Split('.')
    $expectedParts = $Expected.Split('.')

    for ($i = 0; $i -lt $expectedParts.Count; $i++) {
        $expectedPart = $expectedParts[$i]

        if ($expectedPart -eq 'x') {
            # Once a wildcard is encountered, all remaining
            # components are intentionally unconstrained.
            return $true
        }

        if ($i -ge $actualParts.Count) {
            return $false
        }

        if ($actualParts[$i] -ne $expectedPart) {
            return $false
        }
    }

    # If no wildcard was specified, require an exact component count.
    return $actualParts.Count -eq $expectedParts.Count
}

# ============================================================================
# Software discovery
# ============================================================================

<#
.SYNOPSIS
    Resolves the executable backing a Windows service.

.DESCRIPTION
    Locates the requested Windows service and extracts its executable path
    from BinaryPathName.

    Falls back to Win32_Service through CIM when BinaryPathName is not exposed
    by Get-Service.

    Handles both quoted and unquoted executable paths and verifies that the
    resolved executable exists on disk.
#>
function Get-ServiceExecutablePath {
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName
    )

    $service = Get-Service `
        -Name $ServiceName `
        -ErrorAction SilentlyContinue

    if ($null -eq $service) {
        return [pscustomobject]@{
            Success    = $false
            Service    = $null
            Executable = ''
            Message    = "Service '$ServiceName' was not found."
        }
    }

    $binaryPath = $null

    if ($null -ne $service.PSObject.Properties['BinaryPathName']) {
        $binaryPath = $service.BinaryPathName
    }

    # Windows PowerShell may not expose BinaryPathName through Get-Service.
    # In that case, retrieve PathName from Win32_Service through CIM.
    if ($null -eq $binaryPath -or $binaryPath.Length -eq 0) {
        $escapedServiceName = $ServiceName.Replace("'", "''")

        $cimService = Get-CimInstance `
            -ClassName 'Win32_Service' `
            -Filter "Name='$escapedServiceName'" `
            -ErrorAction SilentlyContinue

        if ($null -ne $cimService) {
            $binaryPath = $cimService.PathName
        }
    }

    if ($null -eq $binaryPath -or $binaryPath.Length -eq 0) {
        return [pscustomobject]@{
            Success    = $false
            Service    = $service
            Executable = ''
            Message    = "Could not obtain BinaryPathName for service '$ServiceName'."
        }
    }

    $executable = ''

    # Example:
    #
    # "C:\Program Files\MySQL\MySQL Server 8.4\bin\mysqld.exe"
    #     --defaults-file="C:\ProgramData\MySQL\..."
    #
    # Quoted paths are straightforward because the closing quote marks
    # the end of the executable path.
    if ($binaryPath.StartsWith('"')) {
        $closingQuote = $binaryPath.IndexOf('"', 1)

        if ($closingQuote -gt 1) {
            $executable = $binaryPath.Substring(
                1,
                $closingQuote - 1
            )
        }
    }
    else {
        # For an unquoted service path, capture through the first .exe.
        # This avoids incorrectly splitting paths containing spaces.
        $match = [regex]::Match(
            $binaryPath,
            '^(?<executable>.*?\.exe)(?:\s|$)',
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        if ($match.Success) {
            $executable = $match.Groups['executable'].Value
        }
    }

    if ($executable.Length -eq 0) {
        return [pscustomobject]@{
            Success    = $false
            Service    = $service
            Executable = ''
            Message    = "Could not parse the executable from service path: $binaryPath"
        }
    }

    if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
        return [pscustomobject]@{
            Success    = $false
            Service    = $service
            Executable = $executable
            Message    = "Service executable was not found: $executable"
        }
    }

    return [pscustomobject]@{
        Success    = $true
        Service    = $service
        Executable = $executable
        Message    = ''
    }
}

<#
.SYNOPSIS
    Resolves executable-based software requirements to an executable path.

.DESCRIPTION
    Resolves software configured using either the Command or Service detection
    strategy.

    Command requirements are located through Get-Command. Service requirements
    are resolved through the Windows service's configured executable.

    WingetPackage requirements are deliberately not resolved here because they
    are package-based rather than executable-based.
#>
function Resolve-SoftwareExecutable {
    param(
        [Parameter(Mandatory)]
        [object]$Software
    )

    $commandName = Get-ConfigValue `
        -Object $Software `
        -Name 'Command' `
        -Default ''

    $serviceName = Get-ConfigValue `
        -Object $Software `
        -Name 'Service' `
        -Default ''

    $hasCommand = (
        $null -ne $commandName -and
        $commandName.Length -gt 0
    )

    $hasService = (
        $null -ne $serviceName -and
        $serviceName.Length -gt 0
    )
    $detection = Get-SoftwareDetectionStrategy `
    -Software $Software

    if (-not $detection.Success) {
        return [pscustomobject]@{
            Success     = $false
            Executable  = ''
            Strategy    = ''
            Service     = $null
            FailureKind = 'Configuration'
            Message     = $detection.Message
        }
    }

    if ($detection.Strategy -eq 'WingetPackage') {
        return [pscustomobject]@{
            Success     = $false
            Executable  = ''
            Strategy    = 'WingetPackage'
            Service     = $null
            FailureKind = 'Configuration'
            Message     = 'WingetPackage requirements do not resolve to an executable.'
        }
    }

    if ($hasCommand -and $hasService) {
        return [pscustomobject]@{
            Success      = $false
            Executable   = ''
            Strategy     = ''
            Service      = $null
            FailureKind  = 'Configuration'
            Message      = 'Specify either Command or Service, not both.'
        }
    }

    if (-not $hasCommand -and -not $hasService) {
        return [pscustomobject]@{
            Success      = $false
            Executable   = ''
            Strategy     = ''
            Service      = $null
            FailureKind  = 'Configuration'
            Message      = 'Specify either Command or Service.'
        }
    }

    if ($hasCommand) {
        $resolvedCommand = Get-Command `
            -Name $commandName `
            -ErrorAction SilentlyContinue

        if ($null -eq $resolvedCommand) {
            return [pscustomobject]@{
                Success      = $false
                Executable   = ''
                Strategy     = 'Command'
                Service      = $null
                FailureKind  = 'Missing'
                Message      = "Command '$commandName' was not found."
            }
        }

        $executable = $resolvedCommand.Path

        if ($null -eq $executable -or $executable.Length -eq 0) {
            $executable = $resolvedCommand.Source
        }

        if ($null -eq $executable -or $executable.Length -eq 0) {
            $executable = $resolvedCommand.Definition
        }

        return [pscustomobject]@{
            Success      = $true
            Executable   = $executable
            Strategy     = 'Command'
            Service      = $null
            FailureKind  = ''
            Message      = ''
        }
    }

    $serviceResult = Get-ServiceExecutablePath `
        -ServiceName $serviceName

    if (-not $serviceResult.Success) {
        $failureKind = if ($null -eq $serviceResult.Service) {
            'Missing'
        }
        else {
            'ServiceExecutable'
        }

        return [pscustomobject]@{
            Success      = $false
            Executable   = $serviceResult.Executable
            Strategy     = 'Service'
            Service      = $serviceResult.Service
            FailureKind  = $failureKind
            Message      = $serviceResult.Message
        }
    }

    return [pscustomobject]@{
        Success      = $true
        Executable   = $serviceResult.Executable
        Strategy     = 'Service'
        Service      = $serviceResult.Service
        FailureKind  = ''
        Message      = ''
    }
}


<#
.SYNOPSIS
    Validates the required runtime state of a service-backed requirement.

.DESCRIPTION
    Checks whether software discovered through the Service strategy satisfies
    its MustBeRunning requirement.

    MustBeRunning defaults to true. The check is not applicable to software
    discovered through Command or WingetPackage.
#>
function Test-RequiredServiceState {
    param(
        [Parameter(Mandatory)]
        [object]$Software,

        [Parameter(Mandatory)]
        [object]$DiscoveryResult
    )

    if ($DiscoveryResult.Strategy -ne 'Service') {
        return [pscustomobject]@{
            Applicable = $false
            Success    = $true
            Message    = ''
        }
    }

    $mustBeRunning = Get-ConfigValue `
        -Object $Software `
        -Name 'MustBeRunning' `
        -Default $true

    if (-not $mustBeRunning) {
        return [pscustomobject]@{
            Applicable = $true
            Success    = $true
            Message    = ''
        }
    }

    if ($null -eq $DiscoveryResult.Service) {
        return [pscustomobject]@{
            Applicable = $true
            Success    = $false
            Message    = 'The configured service was not found.'
        }
    }

    if ($DiscoveryResult.Service.Status -ne 'Running') {
        return [pscustomobject]@{
            Applicable = $true
            Success    = $false
            Message    = "Service is $($DiscoveryResult.Service.Status); expected Running."
        }
    }

    return [pscustomobject]@{
        Applicable = $true
        Success    = $true
        Message    = 'Service is running.'
    }
}

<#
.SYNOPSIS
    Determines how a software requirement should be detected.

.DESCRIPTION
    Identifies whether a software entry uses Command, Service, or WingetPackage
    detection.

    Exactly one detection strategy must be configured. Missing or conflicting
    strategies are returned as configuration errors.
#>
function Get-SoftwareDetectionStrategy {
    param(
        [Parameter(Mandatory)]
        [object]$Software
    )

    $command = Get-ConfigValue `
        -Object $Software `
        -Name 'Command' `
        -Default ''

    $service = Get-ConfigValue `
        -Object $Software `
        -Name 'Service' `
        -Default ''

    $wingetPackage = Get-ConfigValue `
        -Object $Software `
        -Name 'WingetPackage' `
        -Default ''

    $strategies = [System.Collections.Generic.List[string]]::new()

    if ($null -ne $command -and $command.Length -gt 0) {
        $strategies.Add('Command')
    }

    if ($null -ne $service -and $service.Length -gt 0) {
        $strategies.Add('Service')
    }

    if ($null -ne $wingetPackage -and $wingetPackage.Length -gt 0) {
        $strategies.Add('WingetPackage')
    }

    if ($strategies.Count -eq 0) {
        return [pscustomobject]@{
            Success  = $false
            Strategy = ''
            Message  = 'Specify one of Command, Service, or WingetPackage.'
        }
    }

    if ($strategies.Count -gt 1) {
        $configured = $strategies -join ', '

        return [pscustomobject]@{
            Success  = $false
            Strategy = ''
            Message  = "Detection strategies are mutually exclusive. Configured: $configured."
        }
    }

    return [pscustomobject]@{
        Success  = $true
        Strategy = $strategies[0]
        Message  = ''
    }
}


# ============================================================================
# Software checks
# ============================================================================

<#
.SYNOPSIS
    Locates the Winget executable.

.DESCRIPTION
    Attempts to resolve winget.exe and then winget through PowerShell command
    discovery.

    Returns the resolved command when available or null when Winget cannot be
    found.
#>
function Get-WingetCommand {
    $winget = Get-Command `
        -Name 'winget.exe' `
        -ErrorAction SilentlyContinue

    if ($null -eq $winget) {
        $winget = Get-Command `
            -Name 'winget' `
            -ErrorAction SilentlyContinue
    }

    return $winget
}

<#
.SYNOPSIS
    Determines whether a Winget package is installed.

.DESCRIPTION
    Queries Winget for an exact package ID and returns a structured result
    describing whether the package is installed.

    When possible, the installed version is extracted from Winget's output
    using the common envcheck version-normalization logic.
#>
function Get-InstalledWingetPackage {
    param(
        [Parameter(Mandatory)]
        [string]$PackageId,

        [string]$Source = 'winget'
    )

    $winget = Get-WingetCommand

    if ($null -eq $winget) {
        return [pscustomobject]@{
            Success     = $false
            Installed   = $false
            PackageId   = $PackageId
            Version     = ''
            FailureKind = 'WingetUnavailable'
            Message     = 'Winget is not available.'
        }
    }

    $arguments = @(
        'list'
        '--id'
        $PackageId
        '--exact'
        '--disable-interactivity'
        '--accept-source-agreements'
    )

    if ($null -ne $Source -and $Source.Length -gt 0) {
        $arguments += @(
            '--source'
            $Source
        )
    }

    $output = (
        & $winget.Source @arguments 2>&1 |
            Out-String
    ).Trim()

    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        return [pscustomobject]@{
            Success     = $true
            Installed   = $false
            PackageId   = $PackageId
            Version     = ''
            FailureKind = 'Missing'
            Message     = "Winget package '$PackageId' is not installed."
        }
    }

    $matchingLine = $output `
        -split "`r?`n" |
        Where-Object {
            $_ -match [regex]::Escape($PackageId)
        } |
        Select-Object -First 1

    if ($null -eq $matchingLine) {
        return [pscustomobject]@{
            Success     = $true
            Installed   = $false
            PackageId   = $PackageId
            Version     = ''
            FailureKind = 'Missing'
            Message     = "Winget package '$PackageId' is not installed."
        }
    }

    $version = Get-NormalizedVersion `
        -Text $matchingLine

    if ($null -eq $version) {
        $version = ''
    }

    return [pscustomobject]@{
        Success     = $true
        Installed   = $true
        PackageId   = $PackageId
        Version     = $version
        FailureKind = ''
        Message     = 'Installed.'
    }
}

<#
.SYNOPSIS
    Validates a software requirement detected through Winget.

.DESCRIPTION
    Checks whether the configured Winget package is installed and, when a
    version requirement is present, validates the detected package version.

    Version requirements support the same wildcard matching used by other
    software checks, such as 8.4.x.

    The WingetPackage value is also used as the default remediation package
    unless a separate WingetId is explicitly configured.

    Adds the resulting PASS, WARN, or FAIL result to the common envcheck
    result collection.
#>
function Test-WingetPackageRequirement {
    param(
        [Parameter(Mandatory)]
        [object]$Software,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [bool]$Required
    )

    $packageId = Get-ConfigValue `
        -Object $Software `
        -Name 'WingetPackage' `
        -Default ''

    $expectedVersion = Get-ConfigValue `
        -Object $Software `
        -Name 'Version' `
        -Default ''

    $source = Get-ConfigValue `
        -Object $Software `
        -Name 'WingetSource' `
        -Default 'winget'

    $explicitWingetId = Get-ConfigValue `
        -Object $Software `
        -Name 'WingetId' `
        -Default ''

    # If no explicit remediation package was configured, install the same
    # package that is being used for detection.
    if (
        $null -ne $explicitWingetId -and
        $explicitWingetId.Length -gt 0
    ) {
        $remediationPackageId = $explicitWingetId
    }
    else {
        $remediationPackageId = $packageId
    }

    $failureStatus = if ($Required) {
        'FAIL'
    }
    else {
        'WARN'
    }

    # ------------------------------------------------------------------------
    # Detect the package
    # ------------------------------------------------------------------------

    $package = Get-InstalledWingetPackage `
        -PackageId $packageId `
        -Source $source

    if (-not $package.Success) {
        Add-CheckResult `
            -Status $failureStatus `
            -Category 'Software' `
            -Name $Name `
            -Message $package.Message `
            -Required $Required `
            -WingetId $remediationPackageId `
            -WingetSource $source `
            -ExpectedVersion $expectedVersion `
            -FailureKind $package.FailureKind

        return
    }

    # ------------------------------------------------------------------------
    # Verify that the package is installed
    # ------------------------------------------------------------------------

    if (-not $package.Installed) {
        Add-CheckResult `
            -Status $failureStatus `
            -Category 'Software' `
            -Name $Name `
            -Message $package.Message `
            -Required $Required `
            -WingetId $remediationPackageId `
            -WingetSource $source `
            -ExpectedVersion $expectedVersion `
            -FailureKind 'Missing'

        return
    }

    # ------------------------------------------------------------------------
    # Determine whether version validation is required
    # ------------------------------------------------------------------------

    $hasExpectedVersion = (
        $null -ne $expectedVersion -and
        $expectedVersion.Length -gt 0
    )

    $hasDetectedVersion = (
        $null -ne $package.Version -and
        $package.Version.Length -gt 0
    )

    # If no version is required, presence of the package is sufficient.
    if (-not $hasExpectedVersion) {
        $message = if ($hasDetectedVersion) {
            "$($package.Version) installed"
        }
        else {
            'Installed'
        }

        Add-CheckResult `
            -Status 'PASS' `
            -Category 'Software' `
            -Name $Name `
            -Message $message `
            -Required $Required `
            -WingetId $remediationPackageId `
            -WingetSource $source

        return
    }

    # ------------------------------------------------------------------------
    # A version was required, so ensure one could actually be detected
    # ------------------------------------------------------------------------

    if (-not $hasDetectedVersion) {
        Add-CheckResult `
            -Status $failureStatus `
            -Category 'Software' `
            -Name $Name `
            -Message "Installed, but the package version could not be determined. Expected $expectedVersion." `
            -Required $Required `
            -WingetId $remediationPackageId `
            -WingetSource $source `
            -ExpectedVersion $expectedVersion `
            -FailureKind 'VersionDetection'

        return
    }

    # ------------------------------------------------------------------------
    # Compare detected version against the configured version requirement
    #
    # Examples:
    #
    #   Expected 8.4.7 -> exact match required
    #   Expected 8.4.x -> any 8.4 patch version accepted
    #   Expected 8.x   -> any 8.x version accepted
    # ------------------------------------------------------------------------

    $versionMatches = Test-VersionMatch `
        -Actual $package.Version `
        -Expected $expectedVersion

    if (-not $versionMatches) {
        Add-CheckResult `
            -Status $failureStatus `
            -Category 'Software' `
            -Name $Name `
            -Message "Expected $expectedVersion; found $($package.Version)." `
            -Required $Required `
            -WingetId $remediationPackageId `
            -WingetSource $source `
            -ExpectedVersion $expectedVersion `
            -FailureKind 'VersionMismatch'

        return
    }

    # ------------------------------------------------------------------------
    # Requirement satisfied
    # ------------------------------------------------------------------------

    Add-CheckResult `
        -Status 'PASS' `
        -Category 'Software' `
        -Name $Name `
        -Message "$($package.Version) installed (expected $expectedVersion)" `
        -Required $Required `
        -WingetId $remediationPackageId `
        -WingetSource $source `
        -ExpectedVersion $expectedVersion
}

<#
.SYNOPSIS
    Validates all configured software requirements.

.DESCRIPTION
    Coordinates software validation across the supported detection strategies:

        Command
        Service
        WingetPackage

    Executable-backed requirements are checked for installation, version, and
    applicable service state. Winget-backed requirements are delegated to the
    Winget package checker.

    For Command requirements with a WingetId, a missing command is also
    checked against Winget. If Winget reports the package as installed while
    the command cannot be found, the installation is classified as broken
    rather than missing and automatic remediation is suppressed.

    Each requirement ultimately produces a normalized envcheck result.
#>
function Test-SoftwareRequirements {
    param(
        [object[]]$Software = @()
    )

    Write-Section -Name 'Software'

    foreach ($item in $Software) {
        $name = Get-ConfigValue `
            -Object $item `
            -Name 'Name' `
            -Default 'Unnamed software'

        $expectedVersion = Get-ConfigValue `
            -Object $item `
            -Name 'Version' `
            -Default ''

        $versionArguments = @(
            Get-ConfigValue `
                -Object $item `
                -Name 'VersionArguments' `
                -Default @('--version')
        )

        $required = Get-ConfigValue `
            -Object $item `
            -Name 'Required' `
            -Default $true

        $wingetId = Get-ConfigValue `
            -Object $item `
            -Name 'WingetId' `
            -Default ''

        $wingetSource = Get-ConfigValue `
            -Object $item `
            -Name 'WingetSource' `
            -Default 'winget'

        $failureStatus = if ($required) {
            'FAIL'
        }
        else {
            'WARN'
        }

        # --------------------------------------------------------------------
        # Determine the configured detection strategy
        # --------------------------------------------------------------------

        $detection = Get-SoftwareDetectionStrategy `
            -Software $item

        if (-not $detection.Success) {
            Add-CheckResult `
                -Status $failureStatus `
                -Category 'Software' `
                -Name $name `
                -Message $detection.Message `
                -Required $required `
                -FailureKind 'Configuration'

            continue
        }

        # --------------------------------------------------------------------
        # WingetPackage requirements have their own detection path
        # --------------------------------------------------------------------

        if ($detection.Strategy -eq 'WingetPackage') {
            Test-WingetPackageRequirement `
                -Software $item `
                -Name $name `
                -Required $required

            continue
        }

        # --------------------------------------------------------------------
        # Locate Command- or Service-backed software
        # --------------------------------------------------------------------

        $discovery = Resolve-SoftwareExecutable `
            -Software $item

        if (-not $discovery.Success) {

            # -------------------

# ============================================================================
# Environment-variable checks
# ============================================================================

<#
.SYNOPSIS
    Validates required environment variables.

.DESCRIPTION
    Checks whether configured environment variables are available to the
    current PowerShell process.

    Missing required values fail the check. Missing optional values generate
    warnings. Values marked Secret are never written to the console.
#>
function Test-EnvironmentRequirements {
    param(
        [object[]]$Environment = @()
    )

    if ($Environment.Count -eq 0) {
        return
    }

    Write-Section -Name 'Environment'

    foreach ($item in $Environment) {
        $name = Get-ConfigValue `
            -Object $item `
            -Name 'Name' `
            -Default ''

        $required = Get-ConfigValue `
            -Object $item `
            -Name 'Required' `
            -Default $true

        $secret = Get-ConfigValue `
            -Object $item `
            -Name 'Secret' `
            -Default $false

        if ([string]::IsNullOrWhiteSpace($name)) {
            Add-CheckResult `
                -Status 'FAIL' `
                -Category 'Environment' `
                -Name '<unnamed>' `
                -Message 'Environment variable name is missing.' `
                -Required $required

            continue
        }

        $value = [Environment]::GetEnvironmentVariable($name)

        if ([string]::IsNullOrWhiteSpace($value)) {
            $status = if ($required) {
                'FAIL'
            }
            else {
                'WARN'
            }

            Add-CheckResult `
                -Status $status `
                -Category 'Environment' `
                -Name $name `
                -Message 'Not configured.' `
                -Required $required

            continue
        }

        $displayValue = if ($secret) {
            '********'
        }
        else {
            $value
        }

        Add-CheckResult `
            -Status 'PASS' `
            -Category 'Environment' `
            -Name $name `
            -Message $displayValue `
            -Required $required
    }
}


# ============================================================================
# File checks
# ============================================================================

<#
.SYNOPSIS
    Validates required files and their contents.

.DESCRIPTION
    Checks that each configured file exists and is not empty.

    Missing or zero-byte required files fail validation. Missing or zero-byte
    optional files produce warnings.

    Relative paths are evaluated from the current working directory.
#>
function Test-FileRequirements {
    param(
        [object[]]$Files = @()
    )

    if ($Files.Count -eq 0) {
        return
    }

    Write-Section -Name 'Files'

    foreach ($item in $Files) {
        $name = Get-ConfigValue `
            -Object $item `
            -Name 'Name' `
            -Default 'Unnamed file'

        $path = Get-ConfigValue `
            -Object $item `
            -Name 'Path' `
            -Default ''

        $required = Get-ConfigValue `
            -Object $item `
            -Name 'Required' `
            -Default $true

        $failureStatus = if ($required) {
            'FAIL'
        }
        else {
            'WARN'
        }

        if ([string]::IsNullOrWhiteSpace($path)) {
            Add-CheckResult `
                -Status 'FAIL' `
                -Category 'Files' `
                -Name $name `
                -Message 'No file path configured.' `
                -Required $required

            continue
        }

        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Add-CheckResult `
                -Status $failureStatus `
                -Category 'Files' `
                -Name $name `
                -Message "Not found: $path" `
                -Required $required

            continue
        }

        $file = Get-Item `
            -LiteralPath $path `
            -ErrorAction Stop

        if ($file.Length -eq 0) {
            Add-CheckResult `
                -Status $failureStatus `
                -Category 'Files' `
                -Name $name `
                -Message "File is empty: $path" `
                -Required $required `
                -FailureKind 'EmptyFile'

            continue
        }

        Add-CheckResult `
            -Status 'PASS' `
            -Category 'Files' `
            -Name $name `
            -Message "$path ($($file.Length) bytes)" `
            -Required $required
    }
}


# ============================================================================
# TCP connectivity checks
# ============================================================================

<#
.SYNOPSIS
    Tests TCP connectivity to a host and port.

.DESCRIPTION
    Attempts to establish a TCP connection to the specified endpoint within
    the configured timeout.

    Returns true when the connection succeeds and false when the connection
    fails or times out.

    This test validates TCP reachability only. It does not perform
    protocol-level or authentication checks.
#>
function Test-TcpEndpoint {
    param(
        [Parameter(Mandatory)]
        [string]$HostName,

        [Parameter(Mandatory)]
        [int]$Port,

        [int]$TimeoutMs = 3000
    )

    $client = [System.Net.Sockets.TcpClient]::new()

    try {
        $task = $client.ConnectAsync(
            $HostName,
            $Port
        )

        $completed = $task.Wait($TimeoutMs)

        if (-not $completed) {
            return $false
        }

        return $client.Connected
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}



<#
.SYNOPSIS
    Validates configured network connectivity requirements.

.DESCRIPTION
    Checks each configured host and TCP port using Test-TcpEndpoint.

    Required endpoints fail validation when unreachable, while optional
    endpoints generate warnings.
#>
function Test-ConnectivityRequirements {
    param(
        [object[]]$Connectivity = @()
    )

    if ($Connectivity.Count -eq 0) {
        return
    }

    Write-Section -Name 'Connectivity'

    foreach ($item in $Connectivity) {
        $name = Get-ConfigValue `
            -Object $item `
            -Name 'Name' `
            -Default 'Unnamed endpoint'

        $hostName = Get-ConfigValue `
            -Object $item `
            -Name 'Host' `
            -Default ''

        $port = Get-ConfigValue `
            -Object $item `
            -Name 'Port' `
            -Default 0

        $timeoutMs = Get-ConfigValue `
            -Object $item `
            -Name 'TimeoutMs' `
            -Default 3000

        $required = Get-ConfigValue `
            -Object $item `
            -Name 'Required' `
            -Default $true

        if (
            [string]::IsNullOrWhiteSpace($hostName) -or
            $port -lt 1 -or
            $port -gt 65535
        ) {
            Add-CheckResult `
                -Status 'FAIL' `
                -Category 'Connectivity' `
                -Name $name `
                -Message 'Host or port is invalid.' `
                -Required $required

            continue
        }

        $available = Test-TcpEndpoint `
            -HostName $hostName `
            -Port $port `
            -TimeoutMs $timeoutMs

        if ($available) {
            Add-CheckResult `
                -Status 'PASS' `
                -Category 'Connectivity' `
                -Name $name `
                -Message "$hostName`:$port" `
                -Required $required

            continue
        }

        $status = if ($required) {
            'FAIL'
        }
        else {
            'WARN'
        }

        Add-CheckResult `
            -Status $status `
            -Category 'Connectivity' `
            -Name $name `
            -Message "Unable to connect to $hostName`:$port within $timeoutMs ms." `
            -Required $required
    }
}


# ============================================================================
# Bootstrap
# ============================================================================

<#
.SYNOPSIS
    Determines whether a proposed software installation is authorized.

.DESCRIPTION
    Returns true immediately when -Yes is specified.

    In interactive mode, prompts the user before installation. In
    non-interactive mode, returns false unless -Yes has explicitly authorized
    installation.

    This function provides the consent boundary between validation and
    machine-changing remediation.
#>
function Request-InstallationConsent {
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string]$Version = ''
    )

    if ($Yes) {
        return $true
    }

    if ($NonInteractive) {
        return $false
    }

    if ($Version.Length -eq 0) {
        $prompt = "Install $Name using Winget? [y/N]"
    }
    else {
        $prompt = "Install $Name version $Version using Winget? [y/N]"
    }

    $answer = Read-Host $prompt

    return $answer -match '^(?i:y|yes)$'
}


<#
.SYNOPSIS
    Installs a configured package using Winget.

.DESCRIPTION
    Builds and executes the Winget installation command represented by an
    envcheck result.

    Uses exact package IDs, configured package sources, non-interactive
    installer behavior, and accepted package/source agreements.

    Returns true when Winget exits successfully and false otherwise.
#>
function Install-WingetPackage {
    param(
        [Parameter(Mandatory)]
        [object]$Result
    )

    $winget = Get-WingetCommand

    if ($null -eq $winget) {
        Write-Host 'FAIL  Winget is unavailable.' -ForegroundColor Red
        return $false
    }

    $arguments = @(
        'install'
        '--id'
        $Result.WingetId
        '--exact'
        '--accept-source-agreements'
        '--accept-package-agreements'
        '--interactive'
        '--force'
    )

    if (
        $null -ne $Result.ExpectedVersion -and
        $Result.ExpectedVersion.Length -gt 0
    ) {
        $arguments += @(
            '--version'
            $Result.ExpectedVersion
        )
    }

    if (
        $null -ne $Result.WingetSource -and
        $Result.WingetSource.Length -gt 0
    ) {
        $arguments += @(
            '--source'
            $Result.WingetSource
        )
    }

    Write-Host ''
    Write-Host "Installing $($Result.Name)..." -ForegroundColor Cyan

    & $winget.Source @arguments

    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        Write-Host "FAIL  Winget exited with code $exitCode while installing $($Result.Name)." `
            -ForegroundColor Red

        return $false
    }

    Write-Host "PASS  Winget completed installation of $($Result.Name)." `
        -ForegroundColor Green

    return $true
}


<#
.SYNOPSIS
    Offers remediation for missing Winget-managed software.

.DESCRIPTION
    Processes failed software checks that are classified as Missing and have
    an associated Winget package.

    Installation requires user consent unless -Yes was specified.

    Version mismatches are reported but intentionally not remediated in V0.1.
    Packages are processed in configuration/result order.
#>
function Invoke-EnvCheckBootstrap {
    Write-Section -Name 'Bootstrap'

    $missingSoftware = @(
        $script:Results |
            Where-Object {
                $_.Status -ne 'PASS' -and
                $_.FailureKind -eq 'Missing' -and
                $_.WingetId.Length -gt 0
            }
    )

    $versionMismatches = @(
        $script:Results |
            Where-Object {
                $_.FailureKind -eq 'VersionMismatch' -and
                $_.WingetId.Length -gt 0
            }
    )

    foreach ($result in $versionMismatches) {
        $message = "SKIP  $($result.Name): version mismatch remediation is disabled in V0.1."
        Write-Host $message -ForegroundColor Yellow
    }

    if ($missingSoftware.Count -eq 0) {
        Write-Host 'No missing Winget-managed software can be installed.' `
            -ForegroundColor DarkGray

        return
    }

    $wingetCommand = Get-Command `
        -Name 'winget' `
        -ErrorAction SilentlyContinue

    if ($null -eq $wingetCommand) {
        Write-Host 'FAIL  Winget is unavailable. Configured packages cannot be installed.' `
            -ForegroundColor Red

        return
    }

    foreach ($result in $missingSoftware) {
        $approved = Request-InstallationConsent `
            -Name $result.Name `
            -Version $result.ExpectedVersion

        if (-not $approved) {
            Write-Host "SKIP  $($result.Name) was not installed." `
                -ForegroundColor Yellow

            continue
        }

        Install-WingetPackage -Result $result | Out-Null
    }

    Write-Host ''

    Write-Host 'Re-run envcheck so a new process can observe PATH and other environment changes.' `
        -ForegroundColor Cyan
}


# ============================================================================
# Summary
# ============================================================================

<#
.SYNOPSIS
    Writes the final envcheck validation summary.

.DESCRIPTION
    Counts accumulated PASS, WARN, and FAIL results and displays the totals.

    When bootstrap is not active, also indicates when one or more failed
    requirements have Winget remediation available.

    Returns the number of failed checks for use by the script's exit logic.
#>
function Write-EnvCheckSummary {
    $passed = @(
        $script:Results |
            Where-Object {
                $_.Status -eq 'PASS'
            }
    ).Count

    $warnings = @(
        $script:Results |
            Where-Object {
                $_.Status -eq 'WARN'
            }
    ).Count

    $failed = @(
        $script:Results |
            Where-Object {
                $_.Status -eq 'FAIL'
            }
    ).Count

    Write-Section -Name 'Summary'

    Write-Host "$passed passed" -ForegroundColor Green
    Write-Host "$warnings warnings" -ForegroundColor Yellow

    if ($failed -gt 0) {
        Write-Host "$failed failed" -ForegroundColor Red
    }
    else {
        Write-Host "$failed failed" -ForegroundColor Green
    }

    $remediationAvailable = @(
        $script:Results |
            Where-Object {
                $_.FailureKind -eq 'Missing' -and
                $_.WingetId.Length -gt 0
            }
    ).Count -gt 0

    if (-not $Bootstrap -and $remediationAvailable) {
        Write-Host ''

        Write-Host 'Winget remediation is available. Run envcheck again with -Bootstrap to review installations.' `
            -ForegroundColor Cyan
    }

    return $failed
}


# ============================================================================
# Entry point
# ============================================================================

try {
    if ($Yes -and -not $Bootstrap) {
        Write-Warning '-Yes has no effect without -Bootstrap.'
    }

    $configuration = Get-EnvCheckConfig

    $projectName = Get-ConfigValue `
        -Object $configuration `
        -Name 'Name' `
        -Default 'Development Environment'

    Write-Host ''
    Write-Host $projectName -ForegroundColor White
    Write-Host ('=' * $projectName.Length) -ForegroundColor White

    if ($Bootstrap) {
        Write-Host 'Mode: check + bootstrap' -ForegroundColor DarkGray
    }
    else {
        Write-Host 'Mode: check only' -ForegroundColor DarkGray
    }

    $software = Get-ConfigValue `
        -Object $configuration `
        -Name 'Software' `
        -Default @()

    $environment = Get-ConfigValue `
        -Object $configuration `
        -Name 'Environment' `
        -Default @()

    $files = Get-ConfigValue `
        -Object $configuration `
        -Name 'Files' `
        -Default @()

    $connectivity = Get-ConfigValue `
        -Object $configuration `
        -Name 'Connectivity' `
        -Default @()

    Test-SoftwareRequirements -Software @($software)
    Test-EnvironmentRequirements -Environment @($environment)
    Test-FileRequirements -Files @($files)
    Test-ConnectivityRequirements -Connectivity @($connectivity)

    $failedCount = Write-EnvCheckSummary

    if ($Bootstrap) {
        Invoke-EnvCheckBootstrap
    }

    if ($failedCount -gt 0) {
        exit 1
    }

    exit 0
}
catch {
    Write-Host ''
    Write-Host "envcheck error: $($_.Exception.Message)" -ForegroundColor Red

    exit 2
}