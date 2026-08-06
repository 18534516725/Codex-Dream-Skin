[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Root)

$ErrorActionPreference = 'Stop'
$startPath = Join-Path $Root 'scripts\start-dream-skin.ps1'
$source = [System.IO.File]::ReadAllText($startPath)

function Invoke-DreamSkinSingleProcessFixture {
  $isolatedSource = [regex]::Replace(
    $source,
    '(?m)^\.\s+\(Join-Path \$PSScriptRoot ''(?:common-windows|theme-windows)\.ps1''\)\r?\n',
    ''
  )
  $isolatedSource = $isolatedSource.Replace(
    '$Injector = Join-Path $PSScriptRoot ''injector.mjs''',
    '$Injector = ''mock-injector.mjs'''
  )
  $isolatedSource = $isolatedSource.Replace(
    '(Split-Path -Parent $PSScriptRoot)',
    '''mock-skill-root'''
  )
  $script:fixtureError = $null
  function Enter-DreamSkinOperationLock { param([int]$TimeoutMilliseconds); return 'fixture-lock' }
  function Exit-DreamSkinOperationLock { param([object]$Mutex) }
  function Assert-DreamSkinPort { param([int]$Port) }
  function Get-DreamSkinNodeRuntime { return [pscustomobject]@{ Path = 'mock-node.exe' } }
  function Get-DreamSkinCodexInstall {
    return [pscustomobject]@{ PackageRoot = 'C:\\current'; Executable = 'C:\\current\\Codex.exe'; Version = 'fixture' }
  }
  function Get-DreamSkinThemePaths {
    param([string]$StateRoot)
    return [pscustomobject]@{ Root = $StateRoot; Active = (Join-Path $StateRoot 'active-theme') }
  }
  function Ensure-DreamSkinManagedDirectory { param([string]$Path, [string]$Root) }
  function Initialize-DreamSkinThemeStore { param([string]$SkillRoot, [string]$StateRoot); return Get-DreamSkinThemePaths -StateRoot $StateRoot }
  function Test-DreamSkinPaused { param([string]$StateRoot); return $false }
  function Read-DreamSkinState { param([string]$Path); return [pscustomobject]@{} }
  function Get-DreamSkinCodexStatePathCandidate {
    param([object]$State)
    return [pscustomobject]@{ PackageRoot = 'C:\\retired'; Executable = 'C:\\retired\\Codex.exe' }
  }
  function Get-DreamSkinCodexInstallFromState { param([object]$State); return $null }
  function Test-DreamSkinPathEqual { param([string]$Left, [string]$Right); return $false }
  # Deliberately emit one object, matching PowerShell's production call boundary.
  function Get-DreamSkinCodexProcesses { param([object]$Codex); return [pscustomobject]@{ ProcessId = 4242 } }
  function Test-DreamSkinCodexPortOwner { param([int]$Port, [object]$Codex); return $false }

  $previousLocalAppData = $env:LOCALAPPDATA
  $env:LOCALAPPDATA = Join-Path ([System.IO.Path]::GetTempPath()) 'dreamskin-single-process-fixture'
  try {
    try {
      & ([scriptblock]::Create($isolatedSource)) -Port 9335
    } catch {
      $script:fixtureError = $_.Exception.Message
    }
  } finally {
    $env:LOCALAPPDATA = $previousLocalAppData
  }
  return $script:fixtureError
}

$fixtureError = Invoke-DreamSkinSingleProcessFixture
if ($fixtureError -cne 'The saved Codex path is still active but no longer matches a registered OpenAI.Codex package. Close it manually; state was preserved.') {
  throw "A one-process Codex query did not take the preserved-state safety path: $fixtureError"
}

# PowerShell unwraps one emitted process object at the call boundary. Every
# collection that the launcher counts must therefore be materialized explicitly.
$unsafeDirectCounts = [regex]::Matches(
  $source,
  '(?m)(?<!@)\(Get-DreamSkinCodexProcesses\b[^\r\n]*\)\.Count'
)
if ($unsafeDirectCounts.Count -ne 0) {
  throw 'Start script reads .Count from an unmaterialized Codex process query.'
}

foreach ($required in @(
  '$currentProcesses = @(Get-DreamSkinCodexProcesses -Codex $currentCodex)',
  '$savedProcesses = @(Get-DreamSkinCodexProcesses -Codex $savedCodex)',
  '$codexProcesses = @(',
  '@(Get-DreamSkinCodexProcesses -Codex $savedPathCandidate).Count',
  '@(Get-DreamSkinCodexProcesses -Codex $codexToStop)',
  '@(Get-DreamSkinCodexProcesses -Codex $codex).Count'
)) {
  if (-not $source.Contains($required)) {
    throw "Start script no longer materializes the required Codex process collection: $required"
  }
}

$single = @([pscustomobject]@{ ProcessId = 4242 })
$materializedBranchResult = @(
  if ($true) { $single } else { @() }
)
if ($materializedBranchResult.Count -ne 1) {
  throw 'The one-process branch fixture did not preserve its array shape across an if-expression assignment.'
}

Write-Output 'PASS: Windows startup materializes one-process Codex query results before counting.'
