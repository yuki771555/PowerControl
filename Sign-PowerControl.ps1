#Requires -Version 5.1
<#
Signs PowerControl.exe with a code-signing certificate.

Examples:
  .\Sign-PowerControl.ps1 -PfxPath C:\certs\codesign.pfx
  .\Sign-PowerControl.ps1 -CertificateThumbprint ABCD1234...
#>

[CmdletBinding(DefaultParameterSetName = 'Pfx')]
param(
    [Parameter(ParameterSetName = 'Pfx')]
    [string]$PfxPath,

    [Parameter(ParameterSetName = 'Pfx')]
    [securestring]$PfxPassword,

    [Parameter(ParameterSetName = 'Store', Mandatory = $true)]
    [string]$CertificateThumbprint,

    [string]$ExePath = (Join-Path $PSScriptRoot 'PowerControl.exe'),

    [string]$TimestampUrl = 'http://timestamp.digicert.com',

    [string]$SignToolPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Find-SignTool {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath)) {
            throw "signtool.exe was not found at: $ExplicitPath"
        }
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    $fromPath = Get-Command signtool.exe -ErrorAction SilentlyContinue
    if ($fromPath) {
        return $fromPath.Source
    }

    $kitsRoot = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (Test-Path -LiteralPath $kitsRoot) {
        $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'x64' }
        $candidate = Get-ChildItem -LiteralPath $kitsRoot -Recurse -Filter signtool.exe -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match ('\\' + [regex]::Escape($arch) + '\\signtool\.exe$') } |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($candidate) {
            return $candidate.FullName
        }
    }

    throw 'signtool.exe was not found. Install the Windows SDK or pass -SignToolPath.'
}

function Convert-SecureStringToPlainText {
    param([securestring]$SecureString)

    if (-not $SecureString) {
        return $null
    }

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

if (-not (Test-Path -LiteralPath $ExePath)) {
    $buildScript = Join-Path $PSScriptRoot 'Build-PowerControl.bat'
    if (-not (Test-Path -LiteralPath $buildScript)) {
        throw "PowerControl.exe was not found and Build-PowerControl.bat is missing: $ExePath"
    }

    Write-Host 'PowerControl.exe not found. Building it first...'
    & $buildScript
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed with exit code $LASTEXITCODE."
    }
}

$resolvedExe = (Resolve-Path -LiteralPath $ExePath).Path
$signtool = Find-SignTool -ExplicitPath $SignToolPath

$signArgs = @(
    'sign',
    '/fd', 'SHA256',
    '/tr', $TimestampUrl,
    '/td', 'SHA256'
)

if ($PSCmdlet.ParameterSetName -eq 'Store') {
    $signArgs += @('/sha1', $CertificateThumbprint)
}
else {
    if (-not $PfxPath) {
        throw 'Pass -PfxPath for PFX signing, or use -CertificateThumbprint to sign from the certificate store.'
    }
    if (-not (Test-Path -LiteralPath $PfxPath)) {
        throw "PFX file was not found: $PfxPath"
    }
    if (-not $PfxPassword) {
        $PfxPassword = Read-Host -Prompt 'PFX password' -AsSecureString
    }

    # The PFX password is briefly visible in signtool.exe's command line. Prefer -CertificateThumbprint
    # when the certificate is already installed in the Windows certificate store.
    Write-Warning 'PFX password is passed as a command-line argument to signtool.exe. Consider using -CertificateThumbprint instead.'
    $plainPassword = Convert-SecureStringToPlainText -SecureString $PfxPassword
    $signArgs += @('/f', (Resolve-Path -LiteralPath $PfxPath).Path, '/p', $plainPassword)
}

$signArgs += $resolvedExe

Write-Host "Signing $resolvedExe"
& $signtool @signArgs
if ($LASTEXITCODE -ne 0) {
    throw "Signing failed with exit code $LASTEXITCODE."
}

Write-Host 'Verifying signature...'
& $signtool verify /pa /v $resolvedExe
if ($LASTEXITCODE -ne 0) {
    throw "Signature verification failed with exit code $LASTEXITCODE."
}

Write-Host 'PowerControl.exe is signed and verified.'
