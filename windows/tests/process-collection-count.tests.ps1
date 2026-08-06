[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Root)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0
. (Join-Path $Root 'scripts\common-windows.ps1')

$originalProcessQuery = (Get-Command Get-DreamSkinCodexProcessesExcept -CommandType Function).ScriptBlock
try {
  $script:processPoll = 0
  function Get-DreamSkinCodexProcessesExcept {
    param(
      [Parameter(Mandatory = $true)][object]$Codex,
      [AllowEmptyCollection()][int[]]$PreserveProcessIds = @()
    )
    $script:processPoll += 1
    if ($script:processPoll -eq 1) {
      return @(
        [pscustomobject]@{ ProcessId = 2147483001 },
        [pscustomobject]@{ ProcessId = 2147483002 }
      )
    }
    if ($script:processPoll -eq 2) {
      return [pscustomobject]@{ ProcessId = 2147483002 }
    }
    return @()
  }
  function Start-Sleep { param([int]$Milliseconds, [int]$Seconds) }

  Stop-DreamSkinCodex -Codex ([pscustomobject]@{ Executable = 'C:\fixture\Codex.exe' })
  if ($script:processPoll -lt 3) {
    throw 'The stop fixture did not observe the process collection shrink from two items to one and then zero.'
  }
} finally {
  Set-Item Function:\Get-DreamSkinCodexProcessesExcept -Value $originalProcessQuery
  Remove-Item Function:\Start-Sleep -ErrorAction SilentlyContinue
}

$relativePaths = @(
  'scripts\common-windows.ps1',
  'scripts\install-dream-skin.ps1',
  'scripts\restore-dream-skin.ps1',
  'scripts\start-dream-skin.ps1',
  'installer\setup-bootstrap.ps1'
)
$unsafePattern = '(?ms)(?<!@)\(Get-DreamSkin(?:CodexProcesses(?:Except)?|PortListeners|CdpTargets)\b.{0,240}?\)\.Count'
foreach ($relativePath in $relativePaths) {
  $path = Join-Path $Root $relativePath
  $source = [System.IO.File]::ReadAllText($path)
  if ([regex]::IsMatch($source, $unsafePattern)) {
    throw "$relativePath reads .Count from an unmaterialized Dream Skin collection query."
  }
}

$commonSource = [System.IO.File]::ReadAllText((Join-Path $Root 'scripts\common-windows.ps1'))
foreach ($required in @(
  '$listeners = @(Get-DreamSkinPortListeners -Port $Port)',
  '$targets = @(Get-DreamSkinCdpTargets -Port $Port)',
  '$processes = @(Get-DreamSkinCodexProcessesExcept',
  '$remaining = @(Get-DreamSkinCodexProcessesExcept'
)) {
  if (-not $commonSource.Contains($required)) {
    throw "The shared Windows process contract no longer materializes this collection: $required"
  }
}

Write-Output 'PASS: Windows process, listener, and CDP target queries remain arrays at one item.'
