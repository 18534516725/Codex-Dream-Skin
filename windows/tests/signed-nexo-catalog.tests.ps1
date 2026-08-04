[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$Root)

$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'scripts\common-windows.ps1')
. (Join-Path $Root 'scripts\signed-nexo-catalog.ps1')
. (Join-Path $Root 'scripts\theme-windows.ps1')

function Assert-SignedCatalogRejected {
  param(
    [Parameter(Mandatory = $true)][scriptblock]$Action,
    [Parameter(Mandatory = $true)][string]$Label
  )
  $rejected = $false
  try { $null = & $Action } catch { $rejected = $true }
  if (-not $rejected) { throw "Signed Nexo catalog unexpectedly accepted $Label." }
}

$node = Get-DreamSkinNodeRuntime
$keyFixtureSource = @'
const { generateKeyPairSync } = require('node:crypto');
const { privateKey, publicKey } = generateKeyPairSync('ed25519');
process.stdout.write(JSON.stringify({
  privateKey: privateKey.export({ format: 'der', type: 'pkcs8' }).toString('base64'),
  publicKey: publicKey.export({ format: 'der', type: 'spki' }).toString('base64')
}));
'@
$keyFixtureJson = @(& $node.Path -e $keyFixtureSource 2>&1)
if ($LASTEXITCODE -ne 0) { throw "Could not create signed catalog test key: $($keyFixtureJson -join ' ')" }
$keyFixture = ($keyFixtureJson -join '') | ConvertFrom-Json -ErrorAction Stop
$testKeys = @{ 'test-nexo-key' = [string]$keyFixture.publicKey }

function New-SignedNexoEnvelopeJson {
  param([Parameter(Mandatory = $true)][object]$Catalog)
  $payloadJson = $Catalog | ConvertTo-Json -Depth 12 -Compress
  $payloadBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payloadJson))
  $signerSource = @'
const { createPrivateKey, sign } = require('node:crypto');
const privateKey = createPrivateKey({ key: Buffer.from(process.argv[1], 'base64'), format: 'der', type: 'pkcs8' });
process.stdout.write(sign(null, Buffer.from(process.argv[2], 'base64'), privateKey).toString('base64'));
'@
  $signatureOutput = @(& $node.Path -e $signerSource `
    ([string]$keyFixture.privateKey) $payloadBase64 2>&1)
  if ($LASTEXITCODE -ne 0) { throw "Could not sign catalog fixture: $($signatureOutput -join ' ')" }
  return ([ordered]@{
    keyId = 'test-nexo-key'
    payloadBase64 = $payloadBase64
    signatureBase64 = ($signatureOutput -join '')
  } | ConvertTo-Json -Compress)
}

function New-SignedNexoCatalogFixture {
  param(
    [long]$Version = 10,
    [string[]]$Revocations = @(),
    [object[]]$Skins = @(),
    [datetime]$Now = [datetime]::UtcNow
  )
  if ($Skins.Count -eq 0) {
    $Skins = @([ordered]@{
      appearance = 'dark'
      backgroundPath = 'sakura-signal/v2/background.webp'
      backgroundSha256 = ('a' * 64)
      category = 'cinematic'
      id = 'sakura-signal'
      nameEn = 'Sakura Signal'
      nameZh = '樱花信号'
      previewPath = 'sakura-signal/v2/preview.webp'
      previewSha256 = ('b' * 64)
      tags = @('pink')
    })
  }
  return [ordered]@{
    assetOrigin = 'https://nexotoken.net/codex-skins/assets/'
    catalogVersion = $Version
    expiresAt = $Now.AddDays(7).ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [Globalization.CultureInfo]::InvariantCulture)
    issuedAt = $Now.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [Globalization.CultureInfo]::InvariantCulture)
    revocations = $Revocations
    schemaVersion = 1
    skins = $Skins
  }
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "dream-skin-signed-catalog-$PID-$([guid]::NewGuid().ToString('N'))"
New-Item -ItemType Directory -Path $temporaryRoot | Out-Null
try {
  $now = [datetime]::UtcNow
  $catalog = New-SignedNexoCatalogFixture -Now $now
  $envelopeJson = New-SignedNexoEnvelopeJson -Catalog $catalog
  $saved = Import-DreamSkinSignedNexoCatalogEnvelope -EnvelopeJson $envelopeJson `
    -StateRoot $temporaryRoot -PublicKeys $testKeys -Now $now
  if ($saved.CatalogVersion -ne 10 -or $saved.Skins.Count -ne 1) {
    throw 'A valid signed Nexo catalog did not persist its closed-schema content.'
  }
  $cachePath = Get-DreamSkinSignedNexoCatalogCachePath -StateRoot $temporaryRoot
  if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf) -or
    @(Get-ChildItem -LiteralPath $temporaryRoot -Filter '*.tmp' -Force).Count -ne 0) {
    throw 'The signed Nexo catalog cache was not written atomically.'
  }

  $resolved = Resolve-DreamSkinSignedNexoSkin -SkinId 'sakura-signal' `
    -StateRoot $temporaryRoot -PublicKeys $testKeys -Now $now -SkipRefresh
  if ($resolved.Id -cne 'sakura-signal' -or
    $resolved.ImageUri -cne 'https://nexotoken.net/codex-skins/assets/sakura-signal/v2/background.webp' -or
    $resolved.BackgroundSha256 -cne ('a' * 64)) {
    throw 'The verified catalog did not resolve the fixed-origin skin asset.'
  }

  $tamperedEnvelope = $envelopeJson | ConvertFrom-Json
  $tamperedEnvelope.signatureBase64 = [Convert]::ToBase64String((New-Object byte[] 64))
  Assert-SignedCatalogRejected -Label 'an invalid Ed25519 signature' -Action {
    Import-DreamSkinSignedNexoCatalogEnvelope `
      -EnvelopeJson ($tamperedEnvelope | ConvertTo-Json -Compress) `
      -StateRoot $temporaryRoot -PublicKeys $testKeys -Now $now
  }
  if ((Read-DreamSkinSignedNexoCatalogCache -StateRoot $temporaryRoot `
      -PublicKeys $testKeys -Now $now).CatalogVersion -ne 10) {
    throw 'A rejected signed catalog changed the last-known-good cache.'
  }

  $wrongOrigin = New-SignedNexoCatalogFixture -Version 11 -Now $now
  $wrongOrigin.assetOrigin = 'https://example.com/codex-skins/assets/'
  Assert-SignedCatalogRejected -Label 'a non-fixed asset origin' -Action {
    Import-DreamSkinSignedNexoCatalogEnvelope `
      -EnvelopeJson (New-SignedNexoEnvelopeJson -Catalog $wrongOrigin) `
      -StateRoot $temporaryRoot -PublicKeys $testKeys -Now $now
  }

  $badPath = New-SignedNexoCatalogFixture -Version 11 -Now $now
  $badPath.skins[0].backgroundPath = '../background.webp'
  Assert-SignedCatalogRejected -Label 'an unsafe media path' -Action {
    Import-DreamSkinSignedNexoCatalogEnvelope `
      -EnvelopeJson (New-SignedNexoEnvelopeJson -Catalog $badPath) `
      -StateRoot $temporaryRoot -PublicKeys $testKeys -Now $now
  }

  $downgrade = New-SignedNexoCatalogFixture -Version 9 -Now $now
  Assert-SignedCatalogRejected -Label 'a catalog downgrade' -Action {
    Import-DreamSkinSignedNexoCatalogEnvelope `
      -EnvelopeJson (New-SignedNexoEnvelopeJson -Catalog $downgrade) `
      -StateRoot $temporaryRoot -PublicKeys $testKeys -Now $now
  }

  $conflictingVersion = New-SignedNexoCatalogFixture -Version 10 -Now $now `
    -Revocations @('sakura-signal') -Skins @([ordered]@{
      appearance = 'light'; backgroundPath = 'paper-garden/v1/background.webp'
      backgroundSha256 = ('c' * 64); category = 'editorial'; id = 'paper-garden'
      nameEn = 'Paper Garden'; nameZh = '纸上花园'
      previewPath = 'paper-garden/v1/preview.webp'; previewSha256 = ('d' * 64)
      tags = @('paper')
    })
  Assert-SignedCatalogRejected -Label 'different content reusing a cached catalog version' -Action {
    Import-DreamSkinSignedNexoCatalogEnvelope `
      -EnvelopeJson (New-SignedNexoEnvelopeJson -Catalog $conflictingVersion) `
      -StateRoot $temporaryRoot -PublicKeys $testKeys -Now $now
  }

  $revokedCatalog = New-SignedNexoCatalogFixture -Version 11 -Now $now `
    -Revocations @('sakura-signal') -Skins @([ordered]@{
      appearance = 'light'; backgroundPath = 'paper-garden/v1/background.webp'
      backgroundSha256 = ('c' * 64); category = 'editorial'; id = 'paper-garden'
      nameEn = 'Paper Garden'; nameZh = '纸上花园'
      previewPath = 'paper-garden/v1/preview.webp'; previewSha256 = ('d' * 64)
      tags = @('paper')
    })
  $null = Import-DreamSkinSignedNexoCatalogEnvelope `
    -EnvelopeJson (New-SignedNexoEnvelopeJson -Catalog $revokedCatalog) `
    -StateRoot $temporaryRoot -PublicKeys $testKeys -Now $now
  Assert-SignedCatalogRejected -Label 'a revoked id retained by an older cache' -Action {
    Resolve-DreamSkinSignedNexoSkin -SkinId 'sakura-signal' `
      -StateRoot $temporaryRoot -PublicKeys $testKeys -Now $now -SkipRefresh
  }
  Assert-SignedCatalogRejected -Label 'an offline unknown id' -Action {
    Resolve-DreamSkinSignedNexoSkin -SkinId 'unknown-skin' `
      -StateRoot $temporaryRoot -PublicKeys $testKeys -Now $now -SkipRefresh
  }
  $paper = Resolve-DreamSkinSignedNexoSkin -SkinId 'paper-garden' `
    -StateRoot $temporaryRoot -PublicKeys $testKeys -Now $now -SkipRefresh
  if ($paper.Id -cne 'paper-garden') { throw 'A known cached id was unavailable offline.' }

  Assert-SignedCatalogRejected -Label 'an unavailable release signing key' -Action {
    Read-DreamSkinSignedNexoCatalogCache -StateRoot $temporaryRoot -PublicKeys @{} -Now $now
  }

  $staleRoot = Join-Path $temporaryRoot 'stale'
  New-Item -ItemType Directory -Path $staleRoot | Out-Null
  $staleIssuedAt = $now.AddDays(-8)
  $staleCatalog = New-SignedNexoCatalogFixture -Version 1 -Now $staleIssuedAt `
    -Revocations @('sakura-signal') -Skins @([ordered]@{
      appearance = 'light'; backgroundPath = 'paper-garden/v1/background.webp'
      backgroundSha256 = ('c' * 64); category = 'editorial'; id = 'paper-garden'
      nameEn = 'Paper Garden'; nameZh = '纸上花园'
      previewPath = 'paper-garden/v1/preview.webp'; previewSha256 = ('d' * 64)
      tags = @('paper')
    })
  $null = Import-DreamSkinSignedNexoCatalogEnvelope `
    -EnvelopeJson (New-SignedNexoEnvelopeJson -Catalog $staleCatalog) `
    -StateRoot $staleRoot -PublicKeys $testKeys -Now $staleIssuedAt
  $stale = Read-DreamSkinSignedNexoCatalogCache `
    -StateRoot $staleRoot -PublicKeys $testKeys -Now $now
  if (-not $stale.IsStale) { throw 'An expired verified cache was not marked stale.' }
  Assert-SignedCatalogRejected -Label 'a stale remote-only skin' -Action {
    Resolve-DreamSkinSignedNexoSkin -SkinId 'paper-garden' `
      -StateRoot $staleRoot -PublicKeys $testKeys -Now $now -SkipRefresh
  }
  Assert-SignedCatalogRejected -Label 'an id revoked by a stale signed catalog' -Action {
    Resolve-DreamSkinSignedNexoSkin -SkinId 'sakura-signal' `
      -StateRoot $staleRoot -PublicKeys $testKeys -Now $now -SkipRefresh
  }
  $script:DreamSkinSignedNexoPublicKeys = $testKeys
  try {
    Assert-SignedCatalogRejected -Label 'an embedded id revoked by a stale signed catalog' -Action {
      Resolve-DreamSkinNexoApplyUri -Uri 'dreamskin://apply?skin=sakura-signal' `
        -StateRoot $staleRoot -Now $now -SkipCatalogRefresh
    }
    $embedded = Resolve-DreamSkinNexoApplyUri -Uri 'dreamskin://apply?skin=stellar-voyager' `
      -StateRoot $staleRoot -Now $now -SkipCatalogRefresh
    if ($embedded.Id -cne 'stellar-voyager' -or
      $embedded.ImageUri -notlike 'https://nexotoken.net/codex-skins/originals/*') {
      throw 'A non-revoked embedded skin was not retained while the signed cache was stale.'
    }
  } finally {
    $script:DreamSkinSignedNexoPublicKeys = @{}
  }

  $expiredRoot = Join-Path $temporaryRoot 'expired-import'
  New-Item -ItemType Directory -Path $expiredRoot | Out-Null
  Assert-SignedCatalogRejected -Label 'an expired network catalog' -Action {
    Import-DreamSkinSignedNexoCatalogEnvelope `
      -EnvelopeJson (New-SignedNexoEnvelopeJson -Catalog $staleCatalog) `
      -StateRoot $expiredRoot -PublicKeys $testKeys -Now $now
  }

  Write-Output 'Signed Nexo catalog tests passed.'
} finally {
  if (Test-Path -LiteralPath $temporaryRoot) {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}
