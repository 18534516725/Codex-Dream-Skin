[CmdletBinding()]
param(
  [switch]$Json,
  [switch]$Interactive,
  [switch]$Auto,
  [switch]$InstallPending
)

$ErrorActionPreference = 'Stop'
$engineRoot = Split-Path -Parent $PSScriptRoot
$versionPath = Join-Path $engineRoot 'VERSION'
$repository = '18534516725/Codex-Dream-Skin'
$releasePage = "https://github.com/$repository/releases/latest"
$stateRoot = Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'
$updateRoot = Join-Path $stateRoot 'updates'
$pendingPath = Join-Path $updateRoot 'pending-update.json'
$lastCheckPath = Join-Path $updateRoot 'last-update-check.txt'
$commonPath = Join-Path $PSScriptRoot 'common-windows.ps1'
if (Test-Path -LiteralPath $commonPath -PathType Leaf) { . $commonPath }

function ConvertTo-DreamSkinVersion {
  param([Parameter(Mandatory = $true)][string]$Value)
  $normalized = $Value.Trim().TrimStart('v', 'V')
  if ($normalized -cnotmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
    throw "Invalid release version: $Value"
  }
  $parsed = $null
  if (-not [version]::TryParse($normalized, [ref]$parsed)) {
    throw "Invalid release version: $Value"
  }
  return $parsed
}

function Test-DreamSkinCodexRunning {
  if (Get-Command Get-DreamSkinRegisteredCodexInstalls -ErrorAction SilentlyContinue) {
    try {
      foreach ($registered in @(Get-DreamSkinRegisteredCodexInstalls)) {
        if (@(Get-DreamSkinCodexProcesses -Codex $registered).Count -gt 0) { return $true }
      }
      return $false
    } catch {}
  }
  return @(Get-Process -Name 'Codex' -ErrorAction SilentlyContinue).Count -gt 0
}

function Invoke-DreamSkinUpdateDownload {
  param([Parameter(Mandatory = $true)][string]$Uri, [Parameter(Mandatory = $true)][string]$OutFile)
  $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -OutFile $OutFile -PassThru -MaximumRedirection 5 `
    -Headers @{ 'User-Agent' = 'CodexDreamSkin-AutoUpdate' } -TimeoutSec 180
  $hostName = $response.BaseResponse.ResponseUri.Host.ToLowerInvariant()
  if ($hostName -notin @('github.com', 'objects.githubusercontent.com', 'release-assets.githubusercontent.com')) {
    throw "Update download redirected to an unapproved host: $hostName"
  }
  if (-not (Test-Path -LiteralPath $OutFile -PathType Leaf) -or
    (Get-Item -LiteralPath $OutFile).Length -le 0) {
    throw 'The downloaded update file is empty.'
  }
}

function Save-DreamSkinPendingUpdate {
  param([Parameter(Mandatory = $true)][string]$LatestVersion)
  New-Item -ItemType Directory -Path $updateRoot -Force | Out-Null
  $versionDirectory = Join-Path $updateRoot "v$LatestVersion"
  New-Item -ItemType Directory -Path $versionDirectory -Force | Out-Null
  $setupName = "CodexDreamSkin-Setup-v$LatestVersion.exe"
  $checksumName = 'SHA256SUMS.txt'
  $baseUri = "https://github.com/$repository/releases/download/v$LatestVersion"
  $setupPath = Join-Path $versionDirectory $setupName
  $checksumPath = Join-Path $versionDirectory $checksumName
  Invoke-DreamSkinUpdateDownload -Uri "$baseUri/$checksumName" -OutFile $checksumPath
  Invoke-DreamSkinUpdateDownload -Uri "$baseUri/$setupName" -OutFile $setupPath
  if ((Get-Item -LiteralPath $setupPath).Length -gt 128MB) {
    throw 'The update installer exceeds the 128 MiB safety limit.'
  }
  $checksumText = ([System.IO.File]::ReadAllText($checksumPath)).Trim()
  $match = [regex]::Match($checksumText, "\A([a-f0-9]{64})  $([regex]::Escape($setupName))\z")
  if (-not $match.Success) { throw 'The update checksum file has an invalid format.' }
  $expectedHash = $match.Groups[1].Value
  $actualHash = (Get-FileHash -LiteralPath $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actualHash -cne $expectedHash) { throw 'The update installer failed SHA-256 validation.' }
  $pending = [pscustomobject]@{
    version = $LatestVersion
    setupPath = $setupPath
    sha256 = $expectedHash
  }
  $temporaryPending = "$pendingPath.writing.$PID"
  [System.IO.File]::WriteAllText($temporaryPending, ($pending | ConvertTo-Json -Compress), [Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPending -Destination $pendingPath -Force
  return $pending
}

function Invoke-DreamSkinPendingUpdate {
  if (-not (Test-Path -LiteralPath $pendingPath -PathType Leaf)) { return $false }
  $pending = [System.IO.File]::ReadAllText($pendingPath) | ConvertFrom-Json
  $version = (ConvertTo-DreamSkinVersion -Value "$($pending.version)").ToString()
  $expectedRoot = [System.IO.Path]::GetFullPath((Join-Path $updateRoot "v$version")) + [IO.Path]::DirectorySeparatorChar
  $setupPath = [System.IO.Path]::GetFullPath("$($pending.setupPath)")
  if (-not $setupPath.StartsWith($expectedRoot, [StringComparison]::OrdinalIgnoreCase) -or
    [System.IO.Path]::GetFileName($setupPath) -cne "CodexDreamSkin-Setup-v$version.exe" -or
    -not (Test-Path -LiteralPath $setupPath -PathType Leaf)) {
    throw 'The pending update path is invalid.'
  }
  $actualHash = (Get-FileHash -LiteralPath $setupPath -Algorithm SHA256).Hash.ToLowerInvariant()
  if ($actualHash -cne "$($pending.sha256)") { throw 'The pending update checksum no longer matches.' }
  if (Test-DreamSkinCodexRunning) { return $false }
  $installer = Start-Process -FilePath $setupPath `
    -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru
  if ($installer.ExitCode -ne 0) { throw "The update installer failed with exit code $($installer.ExitCode)." }
  Remove-Item -LiteralPath $pendingPath -Force
  $bootstrap = Join-Path $env:LOCALAPPDATA 'Programs\CodexDreamSkin\setup-bootstrap.ps1'
  if (Test-Path -LiteralPath $bootstrap -PathType Leaf) {
    $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
    Start-Process -FilePath $powershell -WindowStyle Hidden -ArgumentList (
      "-NoProfile -STA -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File `"$bootstrap`" -LaunchTray"
    ) | Out-Null
  }
  return $true
}

function Show-DreamSkinUpdateResult {
  param([Parameter(Mandatory = $true)][object]$Result)
  Add-Type -AssemblyName System.Windows.Forms
  if (-not $Result.updateAvailable) {
    if ($Interactive) {
      [void][System.Windows.Forms.MessageBox]::Show(
        "Codex Dream Skin $($Result.currentVersion) is up to date.", 'Codex Dream Skin Update',
        [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
    }
    return
  }
  $choice = [System.Windows.Forms.MessageBox]::Show(
    "Codex Dream Skin $($Result.latestVersion) is available.`r`n`r`nDownload and install it automatically? Codex will not be closed or restarted.",
    'Codex Dream Skin Update', [System.Windows.Forms.MessageBoxButtons]::YesNo,
    [System.Windows.Forms.MessageBoxIcon]::Information)
  if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) { return }
  $pending = Save-DreamSkinPendingUpdate -LatestVersion $Result.latestVersionNumber
  if (-not (Invoke-DreamSkinPendingUpdate)) {
    [void][System.Windows.Forms.MessageBox]::Show(
      "The verified update has been downloaded. It will install automatically after Codex closes normally.",
      'Codex Dream Skin Update', [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Information)
  }
}

try {
  New-Item -ItemType Directory -Path $updateRoot -Force | Out-Null
  if ($InstallPending) {
    $null = Invoke-DreamSkinPendingUpdate
    exit 0
  }
  if ($Auto -and (Test-Path -LiteralPath $lastCheckPath -PathType Leaf)) {
    $lastCheck = [datetime]::MinValue
    if ([datetime]::TryParseExact(([IO.File]::ReadAllText($lastCheckPath)).Trim(), 'o',
      [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind,
      [ref]$lastCheck) -and ([datetime]::UtcNow - $lastCheck.ToUniversalTime()).TotalHours -lt 24) {
      exit 0
    }
  }
  if (-not (Test-Path -LiteralPath $versionPath -PathType Leaf)) {
    throw "Installed version file is missing: $versionPath"
  }
  $currentText = ([System.IO.File]::ReadAllText($versionPath)).Trim()
  $current = ConvertTo-DreamSkinVersion -Value $currentText
  $headers = @{ Accept = 'application/vnd.github+json'; 'User-Agent' = 'CodexDreamSkin' }
  $previousProtocol = [Net.ServicePointManager]::SecurityProtocol
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repository/releases/latest" `
      -Headers $headers -Method Get -TimeoutSec 12
  } finally {
    [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
  }
  if (-not $release.tag_name) { throw 'GitHub did not return a release tag.' }
  $latest = ConvertTo-DreamSkinVersion -Value "$($release.tag_name)"
  $latestVersion = $latest.ToString()
  $result = [pscustomobject]@{
    currentVersion = "v$currentText"
    latestVersion = "v$latestVersion"
    latestVersionNumber = $latestVersion
    updateAvailable = $latest -gt $current
    releaseUrl = $releasePage
  }
  [IO.File]::WriteAllText($lastCheckPath, [datetime]::UtcNow.ToString('o'), [Text.UTF8Encoding]::new($false))
  if ($Json) { $result | ConvertTo-Json -Compress }
  if ($Interactive -or $Auto) { Show-DreamSkinUpdateResult -Result $result }
  if (-not $Json -and -not $Interactive -and -not $Auto) {
    Write-Host "$($result.currentVersion) -> $($result.latestVersion); update=$($result.updateAvailable)"
  }
} catch {
  if ($Json) { [pscustomobject]@{ error = $_.Exception.Message; releaseUrl = $releasePage } | ConvertTo-Json -Compress }
  if ($Interactive) {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show(
      "Could not check for updates.`r`n`r`n$($_.Exception.Message)", 'Codex Dream Skin Update',
      [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
  }
  if (-not $Json -and -not $Interactive -and -not $Auto) { throw }
  exit 1
}
