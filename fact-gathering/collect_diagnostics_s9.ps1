<#
.SYNOPSIS
  SAS 9.4 Collection Assistant for Deployment Diagnostics (CADDy)

.DESCRIPTION
  Created by SAS Technical Support.

  CADDy collects and zips files commonly needed for SAS 9.4 deployment troubleshooting.

.NOTES
  - Includes extra error handling for file access issues. If a file cannot be read
    (access denied, locked, etc.), CADDy records the issue and continues collecting other files.
  - File access issues are written to FileAccessIssues.txt inside the ZIP (when applicable).
  - A detailed execution log is always written to CADDy_DetailedLog.txt and included in the ZIP.
  - A PowerShell transcript is captured and included in the ZIP.
  - deploymntreg collection is filtered to include only *.xml and *.bak.
  - Also collects system-profile SAS folders (used by some automated installs) if they exist:
      C:\Windows\SysWOW64\config\systemprofile\AppData\Local\SAS
      C:\Windows\SysWOW64\config\systemprofile\AppData\Roaming\SAS
  - Captures SAS Private JRE functionality by running java.exe with several commands and records stdout/stderr + ExitCode.
  - Adds a timeout to JVM invocations so a hung JVM doesn't stall the tool.
  - Optional: Generates file-size manifests for SASHome and SAS Config when -AllowManifest is specified.
  - At completion, the tool displays the full path to the created ZIP file.
  - Run in an elevated PowerShell session if you expect access restrictions.

.LICENSE
Copyright © 2023, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
SPDX-License-Identifier: Apache-2.0
#>

[CmdletBinding()]
param(
  [string]$SASHomeOverride = "",
  [switch]$AllowManifest,
  [string]$Output = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ------------------------------------------------------------------
# Title (ASCII) + Consent Notice
# ------------------------------------------------------------------
$ToolName = "SAS 9.4 Collection Assistant for Deployment Diagnostics (CADDy)"

$banner = @'
=== CADDy v5.5 ============================================================
          SAS 9.4 Collection Assistant for Deployment Diagnostics
===========================================================================
  ____    _    ____   ___       ____    _    ____  ____
 / ___|  / \  / ___| / _ \     / ___|  / \  |  _ \|  _ \ _   _
 \___ \ / _ \ \___ \| (_) |   | |     / _ \ | | | | | | | | | |
  ___) / ___ \ ___) /\__, |   | |___ / ___ \| |_| | |_| | |_| |
 |____/_/   \_\____/   /_/     \____/_/   \_\____/|____/ \__, |
                                                         |___/
														 
===========================================================================
Copyright (c) 2026, SAS Institute Inc., Cary, NC, USA.  All Rights Reserved.
===========================================================================
'@

Write-Host $banner -ForegroundColor Cyan
Write-Host ""

$notice = @"
$ToolName - Diagnostic Collection Notice

This diagnostic collection tool was created by SAS Technical Support to help troubleshoot SAS 9.4 deployment and configuration issues.

The tool may collect information that could be considered private or sensitive, including (but not limited to):
  - Usernames and profile paths
  - Machine and operating system details (for example, msinfo.nfo)
  - Installed software and configuration details
  - Hostnames, domain information, and network-related configuration artifacts
  - SAS logs that may contain environment-specific identifiers

By proceeding, you consent to the collection of this information from the environment where the tool is run.

Note that all information submitted to SAS Technical Support is used in accordance with the SAS Technical Support Policy Regarding Customer Materials in Support Files:
https://support.sas.com/en/technical-support/services-policies/sas-technical-support-policy-regarding-customer-materials-in-support-files.html

Choose an option:
  [A] Agree and proceed
  [D] Decline and cancel
"@

Write-Host $notice -ForegroundColor Yellow

do {
  $resp = Read-Host "Enter A to Agree and proceed, or D to Decline and cancel"
  $resp = $resp.Trim()
} while ($resp -notin @('A','a','D','d'))

if ($resp -in @('D','d')) {
  Write-Host "User declined. Canceling collection." -ForegroundColor Cyan
  exit 1
}

# ---------------------------
# Logging helpers (created immediately after consent)
# ---------------------------
$Global:CADDyRunTimestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$Global:CADDyStagingRoot  = Join-Path $env:TEMP "CADDy_$Global:CADDyRunTimestamp"
New-Item -ItemType Directory -Path $Global:CADDyStagingRoot -Force | Out-Null

$Global:CADDyDetailedLogPath = Join-Path $Global:CADDyStagingRoot "CADDy_DetailedLog.txt"
$Global:CADDyTranscriptPath  = Join-Path $Global:CADDyStagingRoot "CADDy_Transcript.txt"
$Global:CADDyTranscriptStarted = $false

# Timeout for native process invocations used by functional tests (seconds)
$Global:CADDyNativeTimeoutSeconds = 60

function Write-Log {
  param([Parameter(Mandatory=$true)][string]$Message)
  $ts = (Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff")
  $line = "[$ts] $Message"
  try { Add-Content -LiteralPath $Global:CADDyDetailedLogPath -Value $line -Encoding UTF8 } catch { }
  Write-Host $line -ForegroundColor DarkGray
}

function Write-Info($msg) {
  Write-Host "[INFO ] $msg" -ForegroundColor Cyan
  Write-Log "INFO  $msg"
}

function Write-Warn($msg) {
  Write-Warning $msg
  Write-Log "WARN  $msg"
}


# ---------------------------
# Progress helpers
# ---------------------------
$Global:CADDyProgressEnabled = $true
$Global:CADDyProgressTotalSteps = 10
$Global:CADDyProgressStep = 0
function Set-CADDyOverallProgress {
    param(
        [Parameter(Mandatory=$true)][string]$Status
    )
    if (-not $Global:CADDyProgressEnabled) { return }
    $pct = 0
    if ($Global:CADDyProgressTotalSteps -gt 0) {
        $pct = [int](($Global:CADDyProgressStep / $Global:CADDyProgressTotalSteps) * 100)
        if ($pct -gt 100) { $pct = 100 }
    }
    Write-Progress -Id 1 -Activity 'CADDy: Collecting SAS diagnostics' -Status $Status -PercentComplete $pct
}
function Complete-CADDyProgress {
    if (-not $Global:CADDyProgressEnabled) { return }
    Write-Progress -Id 1 -Activity 'CADDy: Collecting SAS diagnostics' -Completed
}
function Write-ErrorDetails {
  param(
    [Parameter(Mandatory=$true)]$ErrorRecord,
    [string]$Context = ""
  )

  try {
    $ex = $ErrorRecord.Exception
    Write-Log "ERROR $Context"
    Write-Log ("ERROR Message: {0}" -f $ErrorRecord.Exception.Message)
    Write-Log ("ERROR Type   : {0}" -f ($ex.GetType().FullName))

    if ($ErrorRecord.InvocationInfo) {
      Write-Log ("ERROR Script  : {0}" -f $ErrorRecord.InvocationInfo.ScriptName)
      Write-Log ("ERROR Line    : {0}" -f $ErrorRecord.InvocationInfo.ScriptLineNumber)
      Write-Log ("ERROR Column  : {0}" -f $ErrorRecord.InvocationInfo.OffsetInLine)
      Write-Log ("ERROR Command : {0}" -f $ErrorRecord.InvocationInfo.MyCommand)
      Write-Log ("ERROR Position: {0}" -f $ErrorRecord.InvocationInfo.PositionMessage)
    }

    if ($ErrorRecord.ScriptStackTrace) {
      Write-Log "ERROR ScriptStackTrace:"
      Write-Log $ErrorRecord.ScriptStackTrace
    }

    if ($ex.InnerException) {
      Write-Log ("ERROR InnerException: {0}" -f $ex.InnerException.Message)
    }
  } catch {
    # Best effort
  }
}

function Stop-CADDyTranscript {
  if ($Global:CADDyTranscriptStarted) {
    try { Stop-Transcript | Out-Null } catch { }
    $Global:CADDyTranscriptStarted = $false
  }
}



# ---------------------------
# Keep the window open when launched via Explorer "Run with PowerShell"
# ---------------------------
function Test-LaunchedFromExplorer {
  try {
    $p = Get-CimInstance Win32_Process -Filter "ProcessId=$PID" -ErrorAction Stop
    if ($p -and $p.ParentProcessId) {
      $parent = Get-Process -Id $p.ParentProcessId -ErrorAction SilentlyContinue
      if ($parent -and $parent.Name -ieq 'explorer') { return $true }
    }
  } catch { }
  return $false
}

$Global:CADDyLaunchedFromExplorer = $false
try { $Global:CADDyLaunchedFromExplorer = Test-LaunchedFromExplorer } catch { $Global:CADDyLaunchedFromExplorer = $false }

function Pause-IfExplorer {
  param([string]$Message = 'Press Enter to close this PowerShell window...')
  if ($Global:CADDyLaunchedFromExplorer) {
    Write-Host ''
    Write-Host $Message -ForegroundColor Yellow
    Read-Host | Out-Null
  }
}
# Start capturing a transcript as well (captures host output)
try {
  Start-Transcript -Path $Global:CADDyTranscriptPath -Append | Out-Null
  $Global:CADDyTranscriptStarted = $true
  Write-Log "Transcript started: $Global:CADDyTranscriptPath"
} catch {
  Write-Log "WARN  Failed to start transcript: $($_.Exception.Message)"
}

Write-Host "User agreed. Proceeding with collection..." -ForegroundColor Green
Write-Log "CADDy started"

# Track file access issues (access denied, locked files, etc.)
$Global:CADDyFileAccessIssues = New-Object System.Collections.Generic.List[string]

function Add-FileAccessIssue {
  param(
    [string]$Action,
    [string]$Path,
    [string]$Message
  )

  $Global:CADDyFileAccessIssues.Add(("{0}: {1} :: {2}" -f $Action, $Path, $Message)) | Out-Null
  Write-Log ("ACCESS {0}: {1} :: {2}" -f $Action, $Path, $Message)
}

function Get-RegistryDefaultValue {
  param(
    [Microsoft.Win32.RegistryHive]$Hive,
    [string]$SubKey,
    [Microsoft.Win32.RegistryView]$View
  )

  try {
    $baseKey = [Microsoft.Win32.RegistryKey]::OpenBaseKey($Hive, $View)
    $key = $baseKey.OpenSubKey($SubKey)
    if ($null -eq $key) { return $null }
    $val = $key.GetValue("")
    if ([string]::IsNullOrWhiteSpace([string]$val)) { return $null }
    return [string]$val
  } catch {
    return $null
  }
}

function Resolve-SASHomeFromRegistry {
  $subKeyPrimary = "SOFTWARE\SAS Institute Inc.\Common Data\Shared Files"

  $sasHome = Get-RegistryDefaultValue -Hive LocalMachine -SubKey $subKeyPrimary -View Registry64
  if ($sasHome) { return $sasHome }

  $sasHome = Get-RegistryDefaultValue -Hive LocalMachine -SubKey $subKeyPrimary -View Registry32
  if ($sasHome) { return $sasHome }

  $subKeyWow = "SOFTWARE\Wow6432Node\SAS Institute Inc.\Shared Files\Common Data"

  $sasHome = Get-RegistryDefaultValue -Hive LocalMachine -SubKey $subKeyWow -View Registry64
  if ($sasHome) { return $sasHome }

  $sasHome = Get-RegistryDefaultValue -Hive LocalMachine -SubKey $subKeyWow -View Registry32
  if ($sasHome) { return $sasHome }

  return $null
}

function Load-RegistryXml {
  param([Parameter(Mandatory=$true)][string]$RegistryXmlPath)

  if (-not (Test-Path -LiteralPath $RegistryXmlPath)) {
    Write-Warn "registry.xml not found at: $RegistryXmlPath"
    return $null
  }

  try {
    return [xml](Get-Content -LiteralPath $RegistryXmlPath -Raw)
  } catch {
    Add-FileAccessIssue -Action "Read" -Path $RegistryXmlPath -Message $_.Exception.Message
    Write-Warn "Failed to parse XML at $RegistryXmlPath. Error: $($_.Exception.Message)"
    return $null
  }
}

function Get-ConfigDirsFromRegistryXmlDoc {
  param([Parameter(Mandatory=$true)][xml]$XmlDoc)

  try {
    $configKeyNodes = $XmlDoc.SelectNodes("//Key[@name='CONFIG']")
    if ($null -eq $configKeyNodes -or $configKeyNodes.Count -eq 0) { return @() }

    $dirs = New-Object System.Collections.Generic.List[string]

    foreach ($configKey in $configKeyNodes) {
      $configChildren = $configKey.SelectNodes("./Key[starts-with(@name,'Configuration')]")
      foreach ($child in $configChildren) {
        $locNode = $child.SelectSingleNode("./Value[@name='location']")
        if ($locNode -and $locNode.Attributes['data']) {
          $loc = [string]$locNode.Attributes['data'].Value
          if (-not [string]::IsNullOrWhiteSpace($loc)) { $dirs.Add($loc) }
        }
      }
    }

    $unique = @()
    foreach ($d in $dirs) { if ($unique -notcontains $d) { $unique += $d } }
    return ,$unique
  } catch {
    Write-Warn "Failed while reading CONFIG from registry.xml. Error: $($_.Exception.Message)"
    return @()
  }
}

function Get-SafeConfigLabel {
  param(
    [Parameter(Mandatory=$true)][string]$ConfigDir,
    [int]$Index = 0
  )

  try {
    $trimmed = $ConfigDir.TrimEnd('\','/')
    $leaf = Split-Path -Path $trimmed -Leaf
    if ([string]::IsNullOrWhiteSpace($leaf)) { $leaf = "Config" }
    $safeLeaf = ($leaf -replace '[^A-Za-z0-9._-]', '_')
    if ([string]::IsNullOrWhiteSpace($safeLeaf)) { $safeLeaf = "Config" }
    if ($Index -gt 0) {
      return ("Config{0}_{1}" -f $Index, $safeLeaf)
    }
    return $safeLeaf
  } catch {
    if ($Index -gt 0) { return ("Config{0}" -f $Index) }
    return "Config"
  }
}

function Get-LevDirectories {
  param(
    [Parameter(Mandatory=$true)][string]$ConfigDir
  )

  try {
    if (-not (Test-Path -LiteralPath $ConfigDir)) { return @() }

    $dirs = @(Get-ChildItem -LiteralPath $ConfigDir -Directory -ErrorAction SilentlyContinue |
      Where-Object { $_.Name -match '^Lev[0-9]$' } |
      Sort-Object Name)

    return @($dirs | ForEach-Object { $_.FullName })
  } catch {
    Write-Warn "Failed while enumerating Lev# directories under '$ConfigDir'. Error: $($_.Exception.Message)"
    return @()
  }
}

function Get-InstallUserFromRegistryXmlDoc {
  param([Parameter(Mandatory=$true)][xml]$XmlDoc)

  try {
    $node = $XmlDoc.SelectSingleNode("//Key[@name='COMMON']/Value[@name='install_user']")
    if ($node -and $node.Attributes['data']) {
      $val = [string]$node.Attributes['data'].Value
      if (-not [string]::IsNullOrWhiteSpace($val)) { return $val }
    }
    return $null
  } catch {
    Write-Warn "Failed while reading install_user from registry.xml. Error: $($_.Exception.Message)"
    return $null
  }
}

function Ensure-Directory {
  param([Parameter(Mandatory=$true)][string]$Path)

  try {
    if (-not (Test-Path -LiteralPath $Path)) {
      New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
    return $true
  } catch {
    Add-FileAccessIssue -Action "CreateDir" -Path $Path -Message $_.Exception.Message
    Write-Warn "Failed to create directory '$Path'. Error: $($_.Exception.Message)"
    return $false
  }
}

function Copy-FolderIfExists {
  <# Copies a folder recursively but continues if individual files are inaccessible. #>
  param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Destination
  )

  if (-not (Test-Path -LiteralPath $Source)) {
    Write-Warn "Source folder not found; skipping: $Source"
    return $false
  }

  if (-not (Ensure-Directory -Path $Destination)) { return $false }
  $sourceNorm = $Source
  try { $sourceNorm = [System.IO.Path]::GetFullPath($Source) } catch { $sourceNorm = $Source }
  $sourceNorm = $sourceNorm.TrimEnd('\')
  $copied = 0
  $failed = 0

  try {
    $items = @(Get-ChildItem -LiteralPath $Source -Recurse -Force -ErrorAction SilentlyContinue)
$totalItems = $items.Count
$idx = 0
$lastUpdate = Get-Date
    foreach ($item in $items) {
      if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
      $fullPath = $item.FullName
$fullNorm = $fullPath
try { $fullNorm = [System.IO.Path]::GetFullPath($fullPath) } catch { $fullNorm = $fullPath }
$relative = $null
if ($fullNorm.StartsWith($sourceNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
  $relative = $fullNorm.Substring($sourceNorm.Length).TrimStart('\')
} else {
  $relative = Split-Path -Path $fullNorm -Leaf
}
      $target = Join-Path $Destination $relative

      if ($item.PSIsContainer) {
        [void](Ensure-Directory -Path $target)
        continue
      }

      try {
        $parent = Split-Path -Path $target -Parent
        [void](Ensure-Directory -Path $parent)
        Copy-Item -LiteralPath $item.FullName -Destination $target -Force -ErrorAction Stop
        $copied++
      } catch {
        $failed++
        Add-FileAccessIssue -Action "CopyFile" -Path $item.FullName -Message $_.Exception.Message
      }
    }

    Write-Info "Copied folder: $Source (files copied: $copied, failed: $failed)"
if ($Global:CADDyProgressEnabled) { Write-Progress -Id 2 -ParentId 1 -Activity 'Copying files' -Completed }
    if ($copied -eq 0 -and $failed -gt 0) { return $false }
    return $true
  } catch {
    Add-FileAccessIssue -Action "CopyFolder" -Path $Source -Message $_.Exception.Message
    Write-Warn "Failed to copy folder '$Source' -> '$Destination'. Error: $($_.Exception.Message)"
    return $false
  }
}

function Copy-FolderFilesByExtension {
  <# Copies only files (recursively) that match a provided list of extensions. #>
  param(
    [Parameter(Mandatory=$true)][string]$Source,
    [Parameter(Mandatory=$true)][string]$Destination,
    [Parameter(Mandatory=$true)][string[]]$IncludeExtensions
  )

  if (-not (Test-Path -LiteralPath $Source)) {
    Write-Warn "Source folder not found; skipping: $Source"
    return $false
  }

  if (-not (Ensure-Directory -Path $Destination)) { return $false }
  $sourceNorm = $Source
  try { $sourceNorm = [System.IO.Path]::GetFullPath($Source) } catch { $sourceNorm = $Source }
  $sourceNorm = $sourceNorm.TrimEnd('\')
  $includeLower = @($IncludeExtensions | ForEach-Object { $_.ToLowerInvariant() })
  $copied = 0
  $failed = 0
  $skipped = 0

  try {
    $files = @(Get-ChildItem -LiteralPath $Source -Recurse -Force -File -ErrorAction SilentlyContinue)
$totalItems = $files.Count
$idx = 0
$lastUpdate = Get-Date
    foreach ($f in $files) {
      if ($f.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { continue }
      $ext = ([string]$f.Extension).ToLowerInvariant()
      if (-not ($includeLower -contains $ext)) { $skipped++; continue }

      $fullPath = $f.FullName
$fullNorm = $fullPath
try { $fullNorm = [System.IO.Path]::GetFullPath($fullPath) } catch { $fullNorm = $fullPath }
$relative = $null
if ($fullNorm.StartsWith($sourceNorm, [System.StringComparison]::OrdinalIgnoreCase)) {
  $relative = $fullNorm.Substring($sourceNorm.Length).TrimStart('\')
} else {
  $relative = Split-Path -Path $fullNorm -Leaf
}
      $target = Join-Path $Destination $relative

      try {
        $parent = Split-Path -Path $target -Parent
        [void](Ensure-Directory -Path $parent)
        Copy-Item -LiteralPath $f.FullName -Destination $target -Force -ErrorAction Stop
        $copied++
      } catch {
        $failed++
        Add-FileAccessIssue -Action "CopyFile" -Path $f.FullName -Message $_.Exception.Message
      }
    }

    Write-Info ("Copied folder (filtered): {0} (files copied: {1}, failed: {2}, skipped: {3})" -f $Source, $copied, $failed, $skipped)
if ($Global:CADDyProgressEnabled) { Write-Progress -Id 2 -ParentId 1 -Activity 'Copying files' -Completed }
    if ($copied -eq 0 -and $failed -gt 0) { return $false }
    return $true
  } catch {
    Add-FileAccessIssue -Action "CopyFolder" -Path $Source -Message $_.Exception.Message
    Write-Warn "Failed to copy folder (filtered) '$Source' -> '$Destination'. Error: $($_.Exception.Message)"
    return $false
  }
}

function Copy-FileIfExists {
  param(
    [Parameter(Mandatory=$true)][string]$SourceFile,
    [Parameter(Mandatory=$true)][string]$DestinationFolder
  )

  if (-not (Test-Path -LiteralPath $SourceFile)) {
    Write-Warn "File not found; skipping: $SourceFile"
    return $false
  }

  if (-not (Ensure-Directory -Path $DestinationFolder)) { return $false }

  try {
    Copy-Item -LiteralPath $SourceFile -Destination $DestinationFolder -Force -ErrorAction Stop
    Write-Info "Copied file: $SourceFile"
    return $true
  } catch {
    Add-FileAccessIssue -Action "CopyFile" -Path $SourceFile -Message $_.Exception.Message
    Write-Warn "Failed to copy file '$SourceFile' -> '$DestinationFolder'. Error: $($_.Exception.Message)"
    return $false
  }
}

function Copy-PlanXmlFilesIfAny {
  param(
    [Parameter(Mandatory=$true)][string]$PlanDir,
    [Parameter(Mandatory=$true)][string]$DestinationFolder
  )

  if (-not (Test-Path -LiteralPath $PlanDir)) {
    Write-Warn "Plan directory not found; skipping: $PlanDir"
    return $false
  }

  if (-not (Ensure-Directory -Path $DestinationFolder)) { return $false }

  try {
    $files = @(Get-ChildItem -LiteralPath $PlanDir -Filter "plan*.xml" -File -ErrorAction SilentlyContinue)
    $unique = @($files | Sort-Object FullName -Unique)

    if ($unique.Count -eq 0) {
      Write-Warn "No plan*.xml files found in: $PlanDir"
      return $false
    }

    $copied = 0
    $failed = 0

    foreach ($f in $unique) {
      try {
        Copy-Item -LiteralPath $f.FullName -Destination $DestinationFolder -Force -ErrorAction Stop
        $copied++
      } catch {
        $failed++
        Add-FileAccessIssue -Action "CopyPlanXml" -Path $f.FullName -Message $_.Exception.Message
      }
    }

    Write-Info "Copied plan XML file(s): $copied (failed: $failed)"
    return ($copied -gt 0)
  } catch {
    Add-FileAccessIssue -Action "CopyPlanXml" -Path $PlanDir -Message $_.Exception.Message
    Write-Warn "Failed while copying plan XML files from '$PlanDir'. Error: $($_.Exception.Message)"
    return $false
  }
}

function Collect-MsinfoNfo {
  param([Parameter(Mandatory=$true)][string]$OutputPath)

  $msinfoExe = Join-Path $env:SystemRoot "System32\\msinfo32.exe"
  if (-not (Test-Path -LiteralPath $msinfoExe)) {
    Write-Warn "msinfo32.exe not found at: $msinfoExe (skipping msinfo.nfo collection)"
    return $false
  }

  try {
    $parent = Split-Path -Path $OutputPath -Parent
    [void](Ensure-Directory -Path $parent)

    if (Test-Path -LiteralPath $OutputPath) {
      Remove-Item -LiteralPath $OutputPath -Force -ErrorAction SilentlyContinue
    }

    Write-Info "Collecting system information (msinfo32) to: $OutputPath"
    $args = '/nfo "' + $OutputPath + '"'
    $null = Start-Process -FilePath $msinfoExe -ArgumentList $args -Wait -NoNewWindow

    if (-not (Test-Path -LiteralPath $OutputPath)) {
      Write-Warn "msinfo32 completed but output file was not created: $OutputPath"
      Add-FileAccessIssue -Action "Msinfo" -Path $OutputPath -Message "Output file not created"
      return $false
    }

    Write-Info "Created: $OutputPath"
    return $true
  } catch {
    Add-FileAccessIssue -Action "Msinfo" -Path $OutputPath -Message $_.Exception.Message
    Write-Warn "Failed to collect msinfo.nfo. Error: $($_.Exception.Message)"
    return $false
  }
}

function Get-UserProfileFolder {
  param([Parameter(Mandatory=$true)][string]$UserName)

  $base = "C:\\Users"
  $direct = Join-Path $base $UserName
  if (Test-Path -LiteralPath $direct) { return $direct }

  $dirs = @(Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue)
  $exact = @($dirs | Where-Object { $_.Name -ieq $UserName })
  if ($exact.Count -gt 0) { return $exact[0].FullName }

  $prefix = @($dirs | Where-Object { $_.Name -ilike ($UserName + "*") })
  if ($prefix.Count -gt 0) { return $prefix[0].FullName }

  return $null
}

function Write-FileSizeManifest {
  <#
    Creates a text manifest of files and sizes under a root directory.
    One line per file: "12.34 MB C:\\full\\path\\file.ext"
  #>
  param(
    [Parameter(Mandatory=$true)][string]$Root,
    [Parameter(Mandatory=$true)][string]$OutFile
  )

  if (-not (Test-Path -LiteralPath $Root)) {
    Write-Warn "Manifest root not found; skipping: $Root"
    return $false
  }

  try {
    $lines = Get-ChildItem -LiteralPath $Root -File -Recurse -Force -ErrorAction SilentlyContinue |
      Sort-Object FullName |
      ForEach-Object {
        $bytes = $_.Length
        $size = if ($bytes -ge 1GB) { "{0:N2} GB" -f ($bytes/1GB) }
        elseif ($bytes -ge 1MB) { "{0:N2} MB" -f ($bytes/1MB) }
        elseif ($bytes -ge 1KB) { "{0:N2} KB" -f ($bytes/1KB) }
        else { "{0} B" -f $bytes }

        "{0,12} {1}" -f $size, $_.FullName
      }

    $lines | Out-File -FilePath $OutFile -Encoding UTF8 -Width 32767
    Write-Info "Created file-size manifest: $OutFile"
    return $true
  } catch {
    Add-FileAccessIssue -Action "Manifest" -Path $Root -Message $_.Exception.Message
    Write-Warn "Failed to create manifest for '$Root'. Error: $($_.Exception.Message)"
    return $false
  }
}

function Invoke-NativeCapture {
  <#
    Runs a native executable and captures stdout/stderr + exit code reliably.
    Adds a timeout to avoid a hung process stalling the tool.

    Timeout behavior:
      - If the process does not exit within TimeoutSeconds, it is killed.
      - ExitCode is recorded as 124 to indicate timeout.
  #>
  param(
    [Parameter(Mandatory=$true)][string]$Exe,
    [Parameter(Mandatory=$true)][string]$Args,
    [Parameter(Mandatory=$true)][string]$OutFile,
    [int]$TimeoutSeconds = 60
  )

  $timedOut = $false

  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = $Args
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true

    $p = New-Object System.Diagnostics.Process
    $p.StartInfo = $psi

    [void]$p.Start()

    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()

    $timeoutMs = [Math]::Max(1, $TimeoutSeconds) * 1000
    $exited = $p.WaitForExit($timeoutMs)

    $exit = $null
    $killed = $false
    $rawExit = $null

    if (-not $exited) {
      $timedOut = $true
      try { $p.Kill(); $killed = $true } catch { }
      try { $p.WaitForExit() | Out-Null } catch { }
      try { $rawExit = $p.ExitCode } catch { $rawExit = $null }
      $exit = 124
    } else {
      $exit = $p.ExitCode
      $rawExit = $exit
    }

    @(
      "Command      : `"$Exe`" $Args",
      "TimeoutSec   : $TimeoutSeconds",
      "TimedOut     : $timedOut",
      "Killed       : $killed",
      "ExitCode     : $exit",
      "RawExitCode  : $(if ($rawExit -ne $null) { $rawExit } else { '' })",
      "",
      "STDOUT:",
      $stdout,
      "",
      "STDERR:",
      $stderr,
      ""
    ) | Out-File -FilePath $OutFile -Append -Encoding UTF8 -Width 32767

    return $exit
  } catch {
    Add-FileAccessIssue -Action "NativeRun" -Path $Exe -Message $_.Exception.Message
    @(
      "Command      : `"$Exe`" $Args",
      "TimeoutSec   : $TimeoutSeconds",
      "FAILED       : $($_.Exception.Message)",
      ""
    ) | Out-File -FilePath $OutFile -Append -Encoding UTF8 -Width 32767
    return 9999
  }
}

function Collect-SASPrivateJreFunctionalTest {
  <#
    Runs java.exe from SAS Private JRE to validate JVM startup.
    Writes output to a file included in the ZIP and returns a hashtable:
      @{ Success = <bool>; ExitCodes = <int[]>; JavaExe = <string>; TimeoutSeconds = <int> }
  #>
  param(
    [Parameter(Mandatory=$true)][string]$SASHome,
    [Parameter(Mandatory=$true)][string]$OutFile,
    [int]$TimeoutSeconds = 60
  )

  $result = @{ Success = $false; ExitCodes = @(); JavaExe = $null; TimeoutSeconds = $TimeoutSeconds }

  try {
    $parent = Split-Path -Path $OutFile -Parent
    [void](Ensure-Directory -Path $parent)

    $preferred = Join-Path $SASHome "SASPrivateJavaRuntimeEnvironment\\9.4\\jre\\bin\\java.exe"
    $javaExe = $null

    if (Test-Path -LiteralPath $preferred) {
      $javaExe = $preferred
    } else {
      $root = Join-Path $SASHome "SASPrivateJavaRuntimeEnvironment"
      if (Test-Path -LiteralPath $root) {
        $javaExe = (Get-ChildItem -LiteralPath $root -Recurse -Force -File -Filter java.exe -ErrorAction SilentlyContinue |
          Where-Object { $_.FullName -match "\\\\jre\\\\bin\\\\java\\.exe$" } |
          Sort-Object FullName |
          Select-Object -First 1 -ExpandProperty FullName)
      }
    }

    $result.JavaExe = $javaExe

    @(
      "$ToolName - SAS Private JRE Functional Test",
      "===========================================",
      "SASHome        : $SASHome",
      "java.exe       : $(if ($javaExe) { $javaExe } else { '<not found>' })",
      "TimeoutSeconds : $TimeoutSeconds",
      "",
      "This test captures stdout/stderr and ExitCode for each invocation.",
      "ExitCode 124 indicates the process timed out and was killed.",
      ""
    ) | Out-File -FilePath $OutFile -Encoding UTF8 -Width 32767

    if (-not $javaExe) {
      "java.exe was not found under SASHome\\SASPrivateJavaRuntimeEnvironment. Skipping JRE functional test." |
        Out-File -FilePath $OutFile -Append -Encoding UTF8 -Width 32767
      Write-Warn "SAS Private JRE java.exe not found; skipping functional test."
      return $result
    }

    $commands = @(
      "-version",
      "-XshowSettings:properties -version",
      "-XshowSettings:vm -version"
    )

    foreach ($args in $commands) {
      "----" | Out-File -FilePath $OutFile -Append -Encoding UTF8 -Width 32767
      $exit = Invoke-NativeCapture -Exe $javaExe -Args $args -OutFile $OutFile -TimeoutSeconds $TimeoutSeconds
      $result.ExitCodes += $exit
    }

    $result.Success = ($result.ExitCodes -contains 0)

    "----" | Out-File -FilePath $OutFile -Append -Encoding UTF8 -Width 32767
    "Functional result: $(if ($result.Success) { 'SUCCESS (one or more invocations returned ExitCode 0)' } else { 'FAILED (no invocation returned ExitCode 0)' })" |
      Out-File -FilePath $OutFile -Append -Encoding UTF8 -Width 32767

    Write-Info "Captured SAS Private JRE functional test output to: $OutFile"
    return $result

  } catch {
    Add-FileAccessIssue -Action "JavaFunctionalTest" -Path $OutFile -Message $_.Exception.Message
    Write-Warn "Failed to capture SAS Private JRE functional test. Error: $($_.Exception.Message)"
    return $result
  }
}

# ---------------------------
# Main
# ---------------------------

try {
  Write-Info "Starting SAS diagnostics collection (CADDy)..."
$Global:CADDyProgressStep = 0
Set-CADDyOverallProgress -Status 'Initializing'
  Write-Log ("User: {0}  Computer: {1}" -f $env:USERNAME, $env:COMPUTERNAME)
  Write-Log ("PowerShell: {0}  Edition: {1}" -f $PSVersionTable.PSVersion, $PSVersionTable.PSEdition)
  Write-Log ("OS: {0}" -f [System.Environment]::OSVersion.VersionString)
  Write-Log ("Script: {0}" -f $MyInvocation.MyCommand.Path)

  # Determine SASHome
  $sasHome = $null
  if (-not [string]::IsNullOrWhiteSpace($SASHomeOverride)) {
    $sasHome = $SASHomeOverride
    Write-Info "Using SASHome override: $sasHome"
  } else {
    $sasHome = Resolve-SASHomeFromRegistry
    if ($sasHome) { Write-Info "SASHome found in registry: $sasHome" }
  }

  if (-not $sasHome) {
    $defaultHome = "C:\\Program Files\\SASHome"
    if (Test-Path -LiteralPath $defaultHome) {
      $sasHome = $defaultHome
      Write-Warn "SASHome not found in registry. Falling back to default existing path: $sasHome"
    } else {
      throw "Unable to determine SASHome from registry and default path does not exist."
    }
  }

  $sasHome = $sasHome.TrimEnd('\','/')
$Global:CADDyProgressStep = 1
Set-CADDyOverallProgress -Status 'Resolved SASHome'
  # Load registry.xml
  $registryXmlPath = Join-Path $sasHome "deploymntreg\registry.xml"
  $xmlDoc = Load-RegistryXml -RegistryXmlPath $registryXmlPath

  $configDirs = @()
  $primaryConfigDir = $null
  $installUserRaw = $null

  if ($xmlDoc) {
    $configDirs = @(
      Get-ConfigDirsFromRegistryXmlDoc -XmlDoc $xmlDoc |
      ForEach-Object { $_.TrimEnd('\','/') }
    )

    if ($configDirs.Count -gt 0) {
      Write-Info ("Config directory location(s) found in registry.xml: " + ($configDirs -join ", "))
      $primaryConfigDir = $configDirs[0]
    } else {
      Write-Info "No CONFIG section / config directory found in registry.xml (this is expected for some installs)."
    }

    $installUserRaw = Get-InstallUserFromRegistryXmlDoc -XmlDoc $xmlDoc
    if ($installUserRaw) { Write-Info "Original install_user found in registry.xml: $installUserRaw" }
    else { Write-Info "install_user not found in registry.xml." }
  } else {
    Write-Warn "Skipping registry.xml parsing (unable to load)."
  }

  # Collect msinfo
  $msinfoCollected = Collect-MsinfoNfo -OutputPath (Join-Path $Global:CADDyStagingRoot "msinfo.nfo")
$Global:CADDyProgressStep = 3
Set-CADDyOverallProgress -Status 'Collected msinfo'

  # Optional: file-size manifests (disabled by default)
  $sasHomeManifestPath = Join-Path $Global:CADDyStagingRoot "Manifest_SASHome_FileSizes.txt"
  $configManifestPath  = Join-Path $Global:CADDyStagingRoot "Manifest_SASConfig_FileSizes.txt"
  $sasHomeManifestCollected = $false
  $configManifestCollected  = $false

  if ($AllowManifest) {
    Write-Info "AllowManifest specified; generating file-size manifests (this may take a while)..."
    $sasHomeManifestCollected = Write-FileSizeManifest -Root $sasHome -OutFile $sasHomeManifestPath

    if ($primaryConfigDir) {
      $configManifestCollected = Write-FileSizeManifest -Root $primaryConfigDir -OutFile $configManifestPath

      for ($i = 0; $i -lt $configDirs.Count; $i++) {
        $cfg = $configDirs[$i]
        $label = Get-SafeConfigLabel -ConfigDir $cfg -Index ($i + 1)
        $perConfigManifestPath = Join-Path $Global:CADDyStagingRoot ("Manifest_SASConfig_{0}_FileSizes.txt" -f $label)
        [void](Write-FileSizeManifest -Root $cfg -OutFile $perConfigManifestPath)
      }
    } else {
      Write-Warn "ConfigDir not available; skipping SAS Config file-size manifest."
    }
  } else {
    Write-Info "Manifest generation disabled by default. To enable, run CADDy with -AllowManifest."
  }

  # SAS Private JRE functional test (with timeout)
  $jreTestPath = Join-Path $Global:CADDyStagingRoot "SASPrivateJRE_FunctionalTest.txt"
  $jreResult = Collect-SASPrivateJreFunctionalTest -SASHome $sasHome -OutFile $jreTestPath -TimeoutSeconds $Global:CADDyNativeTimeoutSeconds
  $jreSuccess = [bool]$jreResult.Success
  $jreJavaExe = [string]$jreResult.JavaExe
  $jreExitCodes = @($jreResult.ExitCodes)
  $jreTimeoutSeconds = [int]$jreResult.TimeoutSeconds
  $jreTimeoutCount = @($jreExitCodes | Where-Object { $_ -eq 124 }).Count

  # Collect folders/files
  $installLogsCollected = Copy-FolderIfExists -Source (Join-Path $sasHome "InstallMisc\\InstallLogs") -Destination (Join-Path $Global:CADDyStagingRoot "SASHome_InstallMisc_InstallLogs")

  # deploymntreg: only copy *.xml and *.bak
  $deploymntregCollected = Copy-FolderFilesByExtension -Source (Join-Path $sasHome "deploymntreg") -Destination (Join-Path $Global:CADDyStagingRoot "SASHome_deploymntreg") -IncludeExtensions @('.xml','.bak')

  # System-profile SAS folders sometimes used by automated installs (SYSTEM account)
  $sysProfileLocalPath   = 'C:\\Windows\\SysWOW64\\config\\systemprofile\\AppData\\Local\\SAS'
  $sysProfileRoamingPath = 'C:\\Windows\\SysWOW64\\config\\systemprofile\\AppData\\Roaming\\SAS'

  $sysProfileLocalCollected   = Copy-FolderIfExists -Source $sysProfileLocalPath   -Destination (Join-Path $Global:CADDyStagingRoot 'SystemProfile_AppData_Local_SAS')
  $sysProfileRoamingCollected = Copy-FolderIfExists -Source $sysProfileRoamingPath -Destination (Join-Path $Global:CADDyStagingRoot 'SystemProfile_AppData_Roaming_SAS')

  $cdIdCollected = Copy-FileIfExists -SourceFile (Join-Path $sasHome "SASDeploymentManager\\9.4\\cd.id") -DestinationFolder (Join-Path $Global:CADDyStagingRoot "SASHome_SASDeploymentManager_9.4")
  $licensesCollected = Copy-FolderIfExists -Source (Join-Path $sasHome "licenses") -Destination (Join-Path $Global:CADDyStagingRoot "SASHome_licenses")
  $setinitCollected = Copy-FileIfExists -SourceFile (Join-Path $sasHome "SASFoundation\\9.4\\core\\sasinst\\setinit.sss") -DestinationFolder (Join-Path $Global:CADDyStagingRoot "SASHome_SASFoundation_9.4_core_sasinst")

  $configLevDirs = @{}
  $configLogsCollected = @{}
  $statusCollected = @{}
  $plansCollected = @{}

  if ($configDirs.Count -gt 0) {
    for ($i = 0; $i -lt $configDirs.Count; $i++) {
      $configDir = $configDirs[$i]
      $label = Get-SafeConfigLabel -ConfigDir $configDir -Index ($i + 1)
      $levDirs = @(Get-LevDirectories -ConfigDir $configDir)
      $configLevDirs[$configDir] = @($levDirs | ForEach-Object { Split-Path -Path $_ -Leaf })
      $configLogsCollected[$configDir] = @{}
      $statusCollected[$configDir] = @{}
      $plansCollected[$configDir] = @{}

      if ($levDirs.Count -eq 0) {
        Write-Warn "No Lev# directories were found under SAS configuration directory: $configDir"
        continue
      }

      Write-Info ("Collecting config-specific artifacts from [{0}] {1}" -f $label, $configDir)

      foreach ($levDir in $levDirs) {
        $levName = Split-Path -Path $levDir -Leaf
        Write-Info ("Collecting Lev-specific artifacts from [{0}] {1}" -f $levName, $levDir)

        $configLogsCollected[$configDir][$levName] = Copy-FolderIfExists `
          -Source (Join-Path $levDir "Logs\Configure") `
          -Destination (Join-Path $Global:CADDyStagingRoot ("Configs\{0}\{1}\Logs_Configure" -f $label, $levName))

        $statusCollected[$configDir][$levName] = Copy-FileIfExists `
          -SourceFile (Join-Path $levDir "ConfigData\status.xml") `
          -DestinationFolder (Join-Path $Global:CADDyStagingRoot ("Configs\{0}\{1}\ConfigData" -f $label, $levName))

        $plansCollected[$configDir][$levName] = Copy-PlanXmlFilesIfAny `
          -PlanDir (Join-Path $levDir "Utilities") `
          -DestinationFolder (Join-Path $Global:CADDyStagingRoot ("Configs\{0}\{1}\Utilities" -f $label, $levName))
      }
    }
  }

  # SDW logs (current user)
  $currentSdwCollected = $false
  $currentSdwPath = Join-Path $env:LOCALAPPDATA "SAS\\SASDeploymentWizard"
  $currentSdwCollected = Copy-FolderIfExists -Source $currentSdwPath -Destination (Join-Path $Global:CADDyStagingRoot "SASDeploymentWizard_CurrentUser")

  # SDW logs (install user)
  $installSdwCollected = $false
  $installUserName = $null
  $installSdwPath = $null

  if ($installUserRaw) {
    if ($installUserRaw -match '\\') { $installUserName = ($installUserRaw -split '\\')[-1] }
    else { $installUserName = $installUserRaw }

    if (-not [string]::IsNullOrWhiteSpace($installUserName)) {
      $profile = Get-UserProfileFolder -UserName $installUserName
      if ($profile) {
        $installSdwPath = Join-Path $profile "AppData\\Local\\SAS\\SASDeploymentWizard"
        if ($installSdwPath -and ($installSdwPath -ne $currentSdwPath)) {
          $installSdwCollected = Copy-FolderIfExists -Source $installSdwPath -Destination (Join-Path $Global:CADDyStagingRoot "SASDeploymentWizard_InstallUser")
        } else {
          Write-Info "Install user SDW path matches current user; no separate copy needed."
        }
      } else {
        Write-Warn "Could not resolve a profile folder under C:\\Users for install user '$installUserName' (raw: '$installUserRaw')."
      }
    }
  }

  # Write file-access issue report
  $issuesPath = Join-Path $Global:CADDyStagingRoot "FileAccessIssues.txt"
  if ($Global:CADDyFileAccessIssues.Count -gt 0) {
    $header = @(
      "$ToolName - File Access Issues",
      "================================",
      "Some files could not be read or copied (access denied, locked, etc.).",
      "CADDy continued collecting other files.",
      "",
      "Issues:"
    )
    ($header + $Global:CADDyFileAccessIssues) | Set-Content -LiteralPath $issuesPath -Encoding ASCII
    Write-Warn "One or more file access issues occurred. See: $issuesPath"
  }

  # Summary
  $summaryPath = Join-Path $Global:CADDyStagingRoot "CollectionSummary.txt"

  $jreExitCodesLine = if ($jreExitCodes.Count -gt 0) { ($jreExitCodes -join ', ') } else { '' }

  @"
$ToolName - Collection Summary
==============================
Collected By (current user) : $env:USERNAME
Computer                    : $env:COMPUTERNAME
Timestamp : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Output (-Output) : $Output
SASHome                      : $sasHome
registry.xml                 : $registryXmlPath
Primary ConfigDir           : $primaryConfigDir
ConfigDirs                  : $(if ($configDirs.Count -gt 0) { $configDirs -join "; " } else { "" })
install_user (raw)           : $installUserRaw
install_user (parsed)        : $installUserName

Collected artifacts:
- File-size manifests enabled (-AllowManifest)    : $AllowManifest
  SASHome manifest                               : $sasHomeManifestCollected $(if ($AllowManifest) { "($sasHomeManifestPath)" } else { "(disabled)" })
  SAS Config manifest                            : $configManifestCollected $(if ($AllowManifest) { "($configManifestPath)" } else { "(disabled)" })
- SAS Private JRE functional test output         : $jreSuccess ($jreTestPath)
  java.exe                                       : $jreJavaExe
  TimeoutSeconds                                 : $jreTimeoutSeconds
  ExitCodes                                      : $jreExitCodesLine
  Timeouts (ExitCode=124)                        : $jreTimeoutCount
- InstallMisc\InstallLogs                        : $installLogsCollected
- deploymntreg (*.xml, *.bak only)               : $deploymntregCollected
- systemprofile AppData\Local\SAS                : $sysProfileLocalCollected ($sysProfileLocalPath)
- systemprofile AppData\Roaming\SAS              : $sysProfileRoamingCollected ($sysProfileRoamingPath)
- SASDeploymentManager\9.4\cd.id                 : $cdIdCollected
- licenses\*                                     : $licensesCollected
- SASFoundation\9.4\core\sasinst\setinit.sss     : $setinitCollected
- Config directories discovered             : $($configDirs.Count)
- Config/Lev collection details :
$(if ($configDirs.Count -gt 0) {
  ($configDirs | ForEach-Object {
    $cfg = $_
    $levDetail = if ($configLevDirs.ContainsKey($cfg) -and $configLevDirs[$cfg].Count -gt 0) {
      (($configLevDirs[$cfg] | ForEach-Object {
        $lev = $_
        "    * {0}`r`n      Logs\Configure : {1}`r`n      status.xml : {2}`r`n      plan*.xml : {3}" -f $lev, $configLogsCollected[$cfg][$lev], $statusCollected[$cfg][$lev], $plansCollected[$cfg][$lev]
      }) -join "`r`n")
    } else {
      "    * No Lev# directories were discovered."
    }
    "  - {0}`r`n{1}" -f $cfg, $levDetail
  }) -join "`r`n"
} else {
  "  - No SAS configuration directories were discovered in registry.xml."
})
- SDW logs (current user)                        : $currentSdwCollected ($currentSdwPath)
- SDW logs (install user)                        : $installSdwCollected $(if ($installSdwPath) { "($installSdwPath)" } else { "" })
- msinfo.nfo                                     : $msinfoCollected
- File access issues recorded                    : $(if ($Global:CADDyFileAccessIssues.Count -gt 0) { "Yes (see FileAccessIssues.txt)" } else { "No" })
- Detailed log                                   : $(Join-Path $Global:CADDyStagingRoot 'CADDy_DetailedLog.txt')
- Transcript                                     : $Global:CADDyTranscriptPath
"@ | Set-Content -LiteralPath $summaryPath -Encoding ASCII

  # Stop transcript BEFORE Compress-Archive so the transcript file is not locked
  Stop-CADDyTranscript

  # Zip
$zipName = "CADDy_SAS94_Diagnostics_$($env:COMPUTERNAME)_$Global:CADDyRunTimestamp.zip"
$zipPath = $null
if (-not [string]::IsNullOrWhiteSpace($Output)) {
  $outPath = $Output
  try { $outPath = [System.IO.Path]::GetFullPath($outPath) } catch { }
  if ($outPath.ToLowerInvariant().EndsWith('.zip')) {
    $outDir = Split-Path -Path $outPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($outDir)) { [void](Ensure-Directory -Path $outDir) }
    $zipPath = $outPath
  } else {
    [void](Ensure-Directory -Path $outPath)
    $zipPath = Join-Path $outPath $zipName
  }
} else {
  $desktop = [Environment]::GetFolderPath('Desktop')
  $zipPath = Join-Path $desktop $zipName
}
# Record the resolved ZIP destination in the summary BEFORE zipping
try { Add-Content -LiteralPath $summaryPath -Encoding ASCII -Value ("ZIP output path : {0}" -f $zipPath) } catch { }
$Global:CADDyProgressStep = 9
Set-CADDyOverallProgress -Status 'Creating ZIP archive'
  try {
    if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue }
    Compress-Archive -Path (Join-Path $Global:CADDyStagingRoot "*") -DestinationPath $zipPath -Force
    Write-Info "Created zip: $zipPath"
  } catch {
    Add-FileAccessIssue -Action "Zip" -Path $zipPath -Message $_.Exception.Message
    Write-Warn "Failed to create zip at '$zipPath'. Error: $($_.Exception.Message)"
    Write-Warn "Staging folder preserved for manual collection: $Global:CADDyStagingRoot"
    throw
  }

  # Cleanup
  try {
    Remove-Item -LiteralPath $Global:CADDyStagingRoot -Recurse -Force
    Write-Info "Cleaned up staging folder: $Global:CADDyStagingRoot"
  } catch {
    Write-Warn "Could not remove staging folder '$Global:CADDyStagingRoot'. Error: $($_.Exception.Message)"
  }

  # Final user-facing ZIP location message
Complete-CADDyProgress
Write-Host ""
  Write-Host "CADDy finished successfully." -ForegroundColor Green
  Write-Host "You can find the .zip package here:" -ForegroundColor Green
  Write-Host ("  {0}" -f $zipPath) -ForegroundColor Green
  # If launched via Explorer, keep the window open long enough for the user to see the ZIP path
  if ($Global:CADDyLaunchedFromExplorer) {
    try { Start-Process -FilePath explorer.exe -ArgumentList ('/select,"' + $zipPath + '"') -ErrorAction SilentlyContinue } catch { }
    Pause-IfExplorer 'Press Enter to close this PowerShell window...'
  }
} catch {
  Write-ErrorDetails -ErrorRecord $_ -Context "Unhandled exception"

  $errFile = Join-Path $Global:CADDyStagingRoot "CADDy_ErrorDetails.txt"

  try {
    $lines = @(
      "$ToolName - Error Details",
      "==========================",
      ("Timestamp: {0}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss")),
      ("User: {0}" -f $env:USERNAME),
      ("Computer: {0}" -f $env:COMPUTERNAME),
      ("Script: {0}" -f $MyInvocation.MyCommand.Path),
      "",
      "Top-level error:",
      ("  {0}" -f $_.Exception.Message),
      "",
      "Full ErrorRecord (Format-List * -Force):"
    )

    $lines | Set-Content -LiteralPath $errFile -Encoding UTF8
    ($_.Exception | Format-List * -Force | Out-String) | Add-Content -LiteralPath $errFile -Encoding UTF8

    if ($_.InvocationInfo) {
      "" | Add-Content -LiteralPath $errFile -Encoding UTF8
      "InvocationInfo:" | Add-Content -LiteralPath $errFile -Encoding UTF8
      ($_.InvocationInfo | Format-List * -Force | Out-String) | Add-Content -LiteralPath $errFile -Encoding UTF8
    }

    if ($_.ScriptStackTrace) {
      "" | Add-Content -LiteralPath $errFile -Encoding UTF8
      "ScriptStackTrace:" | Add-Content -LiteralPath $errFile -Encoding UTF8
      $_.ScriptStackTrace | Add-Content -LiteralPath $errFile -Encoding UTF8
    }

    "" | Add-Content -LiteralPath $errFile -Encoding UTF8
    "Recent PowerShell error buffer ($Error):" | Add-Content -LiteralPath $errFile -Encoding UTF8
    ($Error | Select-Object -First 25 | Format-List * -Force | Out-String) | Add-Content -LiteralPath $errFile -Encoding UTF8

    Write-Warn "Unhandled error occurred. Detailed error report written to: $errFile"
  } catch {
    # ignore
  }

  Stop-CADDyTranscript

# Clear progress bars if they were displayed
try { Complete-CADDyProgress } catch { }

# User-friendly guidance (especially for Explorer 'Run with PowerShell')
Write-Host ''
Write-Host 'CADDy encountered an error and could not complete.' -ForegroundColor Red
Write-Host 'Review the logs below:' -ForegroundColor Yellow
Write-Host ("  Error details : {0}" -f $errFile) -ForegroundColor Yellow
if ($Global:CADDyDetailedLogPath) { Write-Host ("  Detailed log  : {0}" -f $Global:CADDyDetailedLogPath) -ForegroundColor Yellow }
if ($Global:CADDyTranscriptPath)   { Write-Host ("  Transcript    : {0}" -f $Global:CADDyTranscriptPath) -ForegroundColor Yellow }
if ($Global:CADDyStagingRoot)      { Write-Host ("  Staging folder: {0}" -f $Global:CADDyStagingRoot) -ForegroundColor Yellow }
Write-Host ''
Write-Host 'Tip: If you ran this non-elevated, re-run from an Administrator PowerShell session for best results.' -ForegroundColor Yellow
Pause-IfExplorer

# Preserve existing behavior for interactive PowerShell sessions
if ($Global:CADDyLaunchedFromExplorer) { exit 1 } else { throw }
} finally {
  Stop-CADDyTranscript
}
