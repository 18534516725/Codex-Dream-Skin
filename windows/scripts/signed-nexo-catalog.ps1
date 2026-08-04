$script:DreamSkinSignedNexoCatalogUri = 'https://nexotoken.net/api/codex-skins/catalog'
$script:DreamSkinSignedNexoAssetOrigin = 'https://nexotoken.net/codex-skins/assets/'
$script:DreamSkinSignedNexoMaxPayloadBytes = 1MB
$script:DreamSkinSignedNexoMaxEnvelopeBytes = 1536KB
$script:DreamSkinSignedNexoMaxEntries = 500
$script:DreamSkinNexoSigningKeyReleaseGate = `
  'RELEASE_GATE: pin the authorized Ed25519 public key for keyId nexo-skin-2026-01 before publishing remote catalogs.'

# Intentionally empty until the independently authorized production signing key
# ceremony supplies the matching public key. Unknown key ids always fail closed.
$script:DreamSkinSignedNexoPublicKeys = @{}

function Get-DreamSkinSignedNexoCatalogCachePath {
  param([string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'))
  return Join-Path ([IO.Path]::GetFullPath($StateRoot)) 'catalog\signed-nexo-catalog-envelope.json'
}

function Get-DreamSkinSignedNexoExactProperty {
  param(
    [Parameter(Mandatory = $true)][object]$Value,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Label
  )
  $properties = @($Value.PSObject.Properties | Where-Object { $_.Name -ceq $Name })
  if ($properties.Count -ne 1) { throw "$Label is missing the exact $Name field." }
  return $properties[0].Value
}

function Assert-DreamSkinSignedNexoExactKeys {
  param(
    [Parameter(Mandatory = $true)][object]$Value,
    [Parameter(Mandatory = $true)][string[]]$Expected,
    [Parameter(Mandatory = $true)][string]$Label
  )
  if ($null -eq $Value -or $Value -is [string] -or $Value -is [array] -or
    $Value -is [ValueType]) { throw "$Label must be a JSON object." }
  $actual = @($Value.PSObject.Properties | ForEach-Object { $_.Name } | Sort-Object -CaseSensitive)
  $wanted = @($Expected | Sort-Object -CaseSensitive)
  if ($actual.Count -ne $wanted.Count) { throw "$Label has an invalid schema." }
  for ($index = 0; $index -lt $wanted.Count; $index++) {
    if ($actual[$index] -cne $wanted[$index]) { throw "$Label has an invalid schema." }
  }
}

function ConvertFrom-DreamSkinSignedNexoBase64 {
  param(
    [Parameter(Mandatory = $true)][object]$Value,
    [Parameter(Mandatory = $true)][int]$MaximumBytes,
    [Parameter(Mandatory = $true)][string]$Label
  )
  if ($Value -isnot [string] -or $Value.Length -lt 4 -or
    $Value.Length -gt ([Math]::Ceiling($MaximumBytes / 3.0) * 4) -or
    $Value -notmatch '\A(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?\z') {
    throw "$Label is not canonical base64."
  }
  try { $bytes = [Convert]::FromBase64String($Value) } catch { throw "$Label is not canonical base64." }
  if ($bytes.Length -lt 1 -or $bytes.Length -gt $MaximumBytes -or
    [Convert]::ToBase64String($bytes) -cne $Value) {
    throw "$Label is not canonical base64."
  }
  return $bytes
}

function Test-DreamSkinSignedNexoEd25519 {
  param(
    [Parameter(Mandatory = $true)][byte[]]$Payload,
    [Parameter(Mandatory = $true)][byte[]]$Signature,
    [Parameter(Mandatory = $true)][byte[]]$PublicKey
  )
  if ($Signature.Length -ne 64 -or $PublicKey.Length -ne 44) { return $false }
  if (-not (Get-Command Get-DreamSkinNodeRuntime -ErrorAction SilentlyContinue)) {
    throw 'The trusted bundled Node.js runtime is required to verify the signed Nexo catalog.'
  }
  $node = Get-DreamSkinNodeRuntime
  $temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) `
    "dream-skin-catalog-verify-$PID-$([guid]::NewGuid().ToString('N'))"
  New-Item -ItemType Directory -Path $temporaryRoot -ErrorAction Stop | Out-Null
  try {
    $payloadPath = Join-Path $temporaryRoot 'payload.bin'
    $signaturePath = Join-Path $temporaryRoot 'signature.bin'
    $publicKeyPath = Join-Path $temporaryRoot 'public-key.bin'
    [IO.File]::WriteAllBytes($payloadPath, $Payload)
    [IO.File]::WriteAllBytes($signaturePath, $Signature)
    [IO.File]::WriteAllBytes($publicKeyPath, $PublicKey)
    $verifierSource = @'
const { readFileSync } = require('node:fs');
const { createPublicKey, verify } = require('node:crypto');
const payload = readFileSync(process.argv[1]);
const signature = readFileSync(process.argv[2]);
const rawKey = readFileSync(process.argv[3]);
if (signature.length !== 64 || rawKey.length !== 44) process.exit(2);
const key = createPublicKey({ key: rawKey, format: 'der', type: 'spki' });
if (key.asymmetricKeyType !== 'ed25519') process.exit(3);
process.stdout.write(verify(null, payload, key, signature) ? 'valid' : 'invalid');
'@
    $output = @(& $node.Path -e $verifierSource `
      $payloadPath $signaturePath $publicKeyPath 2>&1)
    return $LASTEXITCODE -eq 0 -and ($output -join '').Trim() -ceq 'valid'
  } finally {
    Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
  }
}

function Assert-DreamSkinSignedNexoText {
  param(
    [Parameter(Mandatory = $true)][object]$Value,
    [Parameter(Mandatory = $true)][string]$Label,
    [int]$MaximumLength = 120
  )
  if ($Value -isnot [string] -or $Value.Length -lt 1 -or $Value.Length -gt $MaximumLength -or
    $Value -cne $Value.Trim() -or $Value -match '[\u0000-\u001f\u007f-\u009f]') {
    throw "$Label is invalid."
  }
  return [string]$Value
}

function Test-DreamSkinSignedNexoId {
  param([AllowNull()][object]$Value)
  return [bool]($Value -is [string] -and $Value.Length -le 64 -and
    $Value -match '\A[a-z0-9]+(?:-[a-z0-9]+)*\z')
}

function ConvertFrom-DreamSkinSignedNexoCatalogPayload {
  param(
    [Parameter(Mandatory = $true)][byte[]]$Payload,
    [datetime]$Now = [datetime]::UtcNow,
    [switch]$AllowExpired
  )
  try {
    $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
    $json = $strictUtf8.GetString($Payload)
    $jsonParameters = @{ ErrorAction = 'Stop' }
    # PowerShell 7.5+ converts ISO timestamps to DateTime by default. Preserve
    # the signed text so the canonical UTC check validates the original bytes.
    if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
      $jsonParameters.DateKind = 'String'
    }
    $catalog = $json | ConvertFrom-Json @jsonParameters
  } catch { throw 'The signed Nexo catalog payload is not strict UTF-8 JSON.' }
  Assert-DreamSkinSignedNexoExactKeys -Value $catalog -Label 'Signed Nexo catalog' -Expected @(
    'assetOrigin', 'catalogVersion', 'expiresAt', 'issuedAt', 'revocations', 'schemaVersion', 'skins'
  )
  if ((Get-DreamSkinSignedNexoExactProperty -Value $catalog -Name 'schemaVersion' -Label 'Signed Nexo catalog') -ne 1) {
    throw 'The signed Nexo catalog schema version is unsupported.'
  }
  $versionValue = Get-DreamSkinSignedNexoExactProperty -Value $catalog -Name 'catalogVersion' -Label 'Signed Nexo catalog'
  try { $catalogVersion = [decimal]$versionValue } catch { throw 'The signed Nexo catalog version is invalid.' }
  if ($catalogVersion -lt 1 -or $catalogVersion -gt 9007199254740991 -or
    [decimal]::Truncate($catalogVersion) -ne $catalogVersion) {
    throw 'The signed Nexo catalog version is invalid.'
  }
  if ((Get-DreamSkinSignedNexoExactProperty -Value $catalog -Name 'assetOrigin' -Label 'Signed Nexo catalog') `
      -cne $script:DreamSkinSignedNexoAssetOrigin) {
    throw 'The signed Nexo catalog asset origin is not approved.'
  }
  $issuedAtText = [string](Get-DreamSkinSignedNexoExactProperty -Value $catalog -Name 'issuedAt' -Label 'Signed Nexo catalog')
  $expiresAtText = [string](Get-DreamSkinSignedNexoExactProperty -Value $catalog -Name 'expiresAt' -Label 'Signed Nexo catalog')
  if ($issuedAtText -notmatch '\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z\z' -or
    $expiresAtText -notmatch '\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z\z') {
    throw 'The signed Nexo catalog validity window is not canonical UTC.'
  }
  try {
    $issuedAt = [datetimeoffset]::Parse(
      $issuedAtText,
      [Globalization.CultureInfo]::InvariantCulture,
      [Globalization.DateTimeStyles]::RoundtripKind
    )
    $expiresAt = [datetimeoffset]::Parse(
      $expiresAtText,
      [Globalization.CultureInfo]::InvariantCulture,
      [Globalization.DateTimeStyles]::RoundtripKind
    )
  } catch { throw 'The signed Nexo catalog validity window is invalid.' }
  $nowOffset = [datetimeoffset]$Now.ToUniversalTime()
  $isStale = $expiresAt -le $nowOffset
  if ($issuedAt.Offset -ne [timespan]::Zero -or $expiresAt.Offset -ne [timespan]::Zero -or
    $issuedAt -gt $nowOffset.AddMinutes(5) -or ($isStale -and -not $AllowExpired) -or
    $expiresAt -le $issuedAt -or $expiresAt -gt $issuedAt.AddDays(8)) {
    throw 'The signed Nexo catalog is expired or has an invalid validity window.'
  }

  $skinArray = @($catalog.PSObject.Properties | Where-Object { $_.Name -ceq 'skins' })[0].Value
  $revocationArray = @($catalog.PSObject.Properties | Where-Object { $_.Name -ceq 'revocations' })[0].Value
  if ($skinArray -isnot [array] -or $revocationArray -isnot [array]) {
    throw 'The signed Nexo catalog skins and revocations fields must be arrays.'
  }
  $skinValues = @($skinArray)
  $revocationValues = @($revocationArray)
  if ($skinValues.Count -gt $script:DreamSkinSignedNexoMaxEntries -or
    $revocationValues.Count -gt $script:DreamSkinSignedNexoMaxEntries) {
    throw 'The signed Nexo catalog contains too many entries.'
  }
  $skinIds = @{}
  $skins = @()
  foreach ($skin in $skinValues) {
    Assert-DreamSkinSignedNexoExactKeys -Value $skin -Label 'Signed Nexo skin' -Expected @(
      'appearance', 'backgroundPath', 'backgroundSha256', 'category', 'id', 'nameEn',
      'nameZh', 'previewPath', 'previewSha256', 'tags'
    )
    $id = Get-DreamSkinSignedNexoExactProperty -Value $skin -Name 'id' -Label 'Signed Nexo skin'
    if (-not (Test-DreamSkinSignedNexoId -Value $id) -or $skinIds.ContainsKey($id)) {
      throw 'The signed Nexo catalog contains an invalid or duplicate skin id.'
    }
    $skinIds[$id] = $true
    $appearance = Get-DreamSkinSignedNexoExactProperty -Value $skin -Name 'appearance' -Label 'Signed Nexo skin'
    if ($appearance -isnot [string] -or $appearance -notin @('light', 'dark', 'adaptive')) {
      throw 'The signed Nexo skin appearance is invalid.'
    }
    $backgroundPath = Get-DreamSkinSignedNexoExactProperty -Value $skin -Name 'backgroundPath' -Label 'Signed Nexo skin'
    $previewPath = Get-DreamSkinSignedNexoExactProperty -Value $skin -Name 'previewPath' -Label 'Signed Nexo skin'
    if ($backgroundPath -isnot [string] -or
      $backgroundPath -notmatch ('\A' + [regex]::Escape($id) + '/v[1-9][0-9]*/background\.webp\z') -or
      $previewPath -isnot [string] -or
      $previewPath -notmatch ('\A' + [regex]::Escape($id) + '/v[1-9][0-9]*/preview\.webp\z')) {
      throw 'The signed Nexo skin contains an invalid media path.'
    }
    $backgroundHash = Get-DreamSkinSignedNexoExactProperty -Value $skin -Name 'backgroundSha256' -Label 'Signed Nexo skin'
    $previewHash = Get-DreamSkinSignedNexoExactProperty -Value $skin -Name 'previewSha256' -Label 'Signed Nexo skin'
    if ($backgroundHash -isnot [string] -or $backgroundHash -notmatch '\A[a-f0-9]{64}\z' -or
      $previewHash -isnot [string] -or $previewHash -notmatch '\A[a-f0-9]{64}\z') {
      throw 'The signed Nexo skin contains an invalid media digest.'
    }
    $tagArray = @($skin.PSObject.Properties | Where-Object { $_.Name -ceq 'tags' })[0].Value
    if ($tagArray -isnot [array]) { throw 'The signed Nexo skin tags field must be an array.' }
    $tags = @($tagArray)
    if ($tags.Count -gt 20) { throw 'The signed Nexo skin contains too many tags.' }
    $tagSet = @{}
    foreach ($tag in $tags) {
      $safeTag = Assert-DreamSkinSignedNexoText -Value $tag -Label 'Signed Nexo skin tag' -MaximumLength 64
      if ($tagSet.ContainsKey($safeTag)) { throw 'The signed Nexo skin contains duplicate tags.' }
      $tagSet[$safeTag] = $true
    }
    $skins += [pscustomobject]@{
      Id = [string]$id
      NameZh = Assert-DreamSkinSignedNexoText -Value (Get-DreamSkinSignedNexoExactProperty -Value $skin -Name 'nameZh' -Label 'Signed Nexo skin') -Label 'Signed Nexo skin nameZh'
      NameEn = Assert-DreamSkinSignedNexoText -Value (Get-DreamSkinSignedNexoExactProperty -Value $skin -Name 'nameEn' -Label 'Signed Nexo skin') -Label 'Signed Nexo skin nameEn'
      Category = Assert-DreamSkinSignedNexoText -Value (Get-DreamSkinSignedNexoExactProperty -Value $skin -Name 'category' -Label 'Signed Nexo skin') -Label 'Signed Nexo skin category' -MaximumLength 64
      Appearance = [string]$appearance
      BackgroundPath = [string]$backgroundPath
      BackgroundSha256 = [string]$backgroundHash
      PreviewPath = [string]$previewPath
      PreviewSha256 = [string]$previewHash
      Tags = @($tags)
    }
  }
  $revocations = @()
  $revokedIds = @{}
  foreach ($revocation in $revocationValues) {
    if (-not (Test-DreamSkinSignedNexoId -Value $revocation) -or
      $revokedIds.ContainsKey($revocation) -or $skinIds.ContainsKey($revocation)) {
      throw 'The signed Nexo catalog contains an invalid, duplicate, or published revocation.'
    }
    $revokedIds[$revocation] = $true
    $revocations += [string]$revocation
  }
  return [pscustomobject]@{
    CatalogVersion = [long]$catalogVersion
    IssuedAt = $issuedAt
    ExpiresAt = $expiresAt
    AssetOrigin = $script:DreamSkinSignedNexoAssetOrigin
    Skins = @($skins)
    Revocations = @($revocations)
    IsStale = $isStale
  }
}

function ConvertFrom-DreamSkinSignedNexoEnvelope {
  param(
    [Parameter(Mandatory = $true)][string]$EnvelopeJson,
    [hashtable]$PublicKeys = $script:DreamSkinSignedNexoPublicKeys,
    [datetime]$Now = [datetime]::UtcNow,
    [switch]$AllowExpired
  )
  if ([Text.Encoding]::UTF8.GetByteCount($EnvelopeJson) -lt 1 -or
    [Text.Encoding]::UTF8.GetByteCount($EnvelopeJson) -gt $script:DreamSkinSignedNexoMaxEnvelopeBytes) {
    throw 'The signed Nexo catalog envelope is empty or oversized.'
  }
  try { $envelope = $EnvelopeJson | ConvertFrom-Json -ErrorAction Stop } catch {
    throw 'The signed Nexo catalog envelope is not valid JSON.'
  }
  Assert-DreamSkinSignedNexoExactKeys -Value $envelope -Label 'Signed Nexo catalog envelope' `
    -Expected @('keyId', 'payloadBase64', 'signatureBase64')
  $keyId = Get-DreamSkinSignedNexoExactProperty -Value $envelope -Name 'keyId' -Label 'Signed Nexo catalog envelope'
  if ($keyId -isnot [string] -or $keyId -notmatch '\A[a-z0-9-]{1,64}\z' -or
    $null -eq $PublicKeys -or -not $PublicKeys.ContainsKey($keyId)) {
    throw "$script:DreamSkinNexoSigningKeyReleaseGate Unknown signed catalog key id."
  }
  $payload = ConvertFrom-DreamSkinSignedNexoBase64 `
    -Value (Get-DreamSkinSignedNexoExactProperty -Value $envelope -Name 'payloadBase64' -Label 'Signed Nexo catalog envelope') `
    -MaximumBytes $script:DreamSkinSignedNexoMaxPayloadBytes -Label 'Signed Nexo catalog payload'
  $signature = ConvertFrom-DreamSkinSignedNexoBase64 `
    -Value (Get-DreamSkinSignedNexoExactProperty -Value $envelope -Name 'signatureBase64' -Label 'Signed Nexo catalog envelope') `
    -MaximumBytes 64 -Label 'Signed Nexo catalog signature'
  $publicKey = ConvertFrom-DreamSkinSignedNexoBase64 -Value $PublicKeys[$keyId] `
    -MaximumBytes 44 -Label 'Pinned signed Nexo catalog public key'
  if ($signature.Length -ne 64 -or $publicKey.Length -ne 44 -or
    -not (Test-DreamSkinSignedNexoEd25519 -Payload $payload -Signature $signature -PublicKey $publicKey)) {
    throw 'The signed Nexo catalog signature is invalid.'
  }
  $catalog = ConvertFrom-DreamSkinSignedNexoCatalogPayload `
    -Payload $payload -Now $Now -AllowExpired:$AllowExpired
  return [pscustomobject]@{
    KeyId = [string]$keyId
    EnvelopeJson = $EnvelopeJson
    CatalogVersion = $catalog.CatalogVersion
    IssuedAt = $catalog.IssuedAt
    ExpiresAt = $catalog.ExpiresAt
    AssetOrigin = $catalog.AssetOrigin
    Skins = $catalog.Skins
    Revocations = $catalog.Revocations
    IsStale = $catalog.IsStale
  }
}

function Read-DreamSkinSignedNexoCatalogCache {
  param(
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'),
    [hashtable]$PublicKeys = $script:DreamSkinSignedNexoPublicKeys,
    [datetime]$Now = [datetime]::UtcNow
  )
  $path = Get-DreamSkinSignedNexoCatalogCachePath -StateRoot $StateRoot
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'No last-known-good signed Nexo catalog is available.' }
  if (Get-Command Assert-DreamSkinNoReparseComponents -ErrorAction SilentlyContinue) {
    Assert-DreamSkinNoReparseComponents -Path $path
  }
  if ((Get-Item -LiteralPath $path -Force).Length -gt $script:DreamSkinSignedNexoMaxEnvelopeBytes) {
    throw 'The cached signed Nexo catalog is oversized.'
  }
  return ConvertFrom-DreamSkinSignedNexoEnvelope `
    -EnvelopeJson (Read-DreamSkinUtf8File -Path $path) -PublicKeys $PublicKeys -Now $Now -AllowExpired
}

function Import-DreamSkinSignedNexoCatalogEnvelope {
  param(
    [Parameter(Mandatory = $true)][string]$EnvelopeJson,
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'),
    [hashtable]$PublicKeys = $script:DreamSkinSignedNexoPublicKeys,
    [datetime]$Now = [datetime]::UtcNow
  )
  $candidate = ConvertFrom-DreamSkinSignedNexoEnvelope `
    -EnvelopeJson $EnvelopeJson -PublicKeys $PublicKeys -Now $Now
  $cachePath = Get-DreamSkinSignedNexoCatalogCachePath -StateRoot $StateRoot
  $cacheDirectory = Split-Path -Parent $cachePath
  if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
    $current = Read-DreamSkinSignedNexoCatalogCache `
      -StateRoot $StateRoot -PublicKeys $PublicKeys -Now $Now
    if ($candidate.CatalogVersion -lt $current.CatalogVersion) {
      throw 'The signed Nexo catalog version would downgrade the last-known-good cache.'
    }
    if ($candidate.CatalogVersion -eq $current.CatalogVersion) {
      $candidateContent = [ordered]@{
        skins = @($candidate.Skins)
        revocations = @($candidate.Revocations)
      } | ConvertTo-Json -Depth 8 -Compress
      $currentContent = [ordered]@{
        skins = @($current.Skins)
        revocations = @($current.Revocations)
      } | ConvertTo-Json -Depth 8 -Compress
      if ($candidateContent -cne $currentContent) {
        throw 'The signed Nexo catalog reused a cached version for different content.'
      }
    }
  }
  if (Get-Command Ensure-DreamSkinManagedDirectory -ErrorAction SilentlyContinue) {
    Ensure-DreamSkinManagedDirectory -Path ([IO.Path]::GetFullPath($StateRoot)) -Root ([IO.Path]::GetFullPath($StateRoot))
    Ensure-DreamSkinManagedDirectory -Path $cacheDirectory -Root ([IO.Path]::GetFullPath($StateRoot))
  } else {
    New-Item -ItemType Directory -Path $cacheDirectory -Force -ErrorAction Stop | Out-Null
  }
  Write-DreamSkinUtf8FileAtomically -Path $cachePath -Content ($EnvelopeJson.Trim() + "`r`n")
  return $candidate
}

function Get-DreamSkinSignedNexoRemoteEnvelope {
  $request = [Net.HttpWebRequest][Net.WebRequest]::Create(
    [Uri]::new($script:DreamSkinSignedNexoCatalogUri, [UriKind]::Absolute)
  )
  $request.Method = 'GET'
  $request.Accept = 'application/json'
  $request.UserAgent = 'CodexDreamSkin/1 signed-nexo-catalog'
  $request.AllowAutoRedirect = $false
  $request.Timeout = 10000
  $request.ReadWriteTimeout = 20000
  $response = [Net.HttpWebResponse]$request.GetResponse()
  try {
    if ([int]$response.StatusCode -ne 200 -or
      $response.ResponseUri.AbsoluteUri -cne $script:DreamSkinSignedNexoCatalogUri) {
      throw 'The fixed signed Nexo catalog endpoint returned an unexpected status or redirect.'
    }
    $contentType = ("$($response.ContentType)" -split ';', 2)[0].Trim().ToLowerInvariant()
    if ($contentType -cne 'application/json') { throw 'The fixed signed Nexo catalog response is not JSON.' }
    if ($response.ContentLength -gt $script:DreamSkinSignedNexoMaxEnvelopeBytes) {
      throw 'The fixed signed Nexo catalog response is oversized.'
    }
    $input = $response.GetResponseStream()
    $memory = [IO.MemoryStream]::new()
    try {
      $buffer = New-Object byte[] 16384
      [int]$written = 0
      while (($read = $input.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $written += $read
        if ($written -gt $script:DreamSkinSignedNexoMaxEnvelopeBytes) {
          throw 'The fixed signed Nexo catalog response is oversized.'
        }
        $memory.Write($buffer, 0, $read)
      }
      if ($written -lt 1) { throw 'The fixed signed Nexo catalog response is empty.' }
      $strictResponseUtf8 = [Text.UTF8Encoding]::new($false, $true)
      $json = $strictResponseUtf8.GetString($memory.ToArray())
    } finally {
      $memory.Dispose()
      $input.Dispose()
    }
  } finally { $response.Dispose() }
  if ([Text.Encoding]::UTF8.GetByteCount($json) -gt $script:DreamSkinSignedNexoMaxEnvelopeBytes) {
    throw 'The fixed signed Nexo catalog response is oversized.'
  }
  try { $wrapper = $json | ConvertFrom-Json -ErrorAction Stop } catch {
    throw 'The fixed signed Nexo catalog response is invalid JSON.'
  }
  Assert-DreamSkinSignedNexoExactKeys -Value $wrapper -Label 'Signed Nexo catalog response' `
    -Expected @('data', 'success')
  $success = Get-DreamSkinSignedNexoExactProperty -Value $wrapper -Name 'success' -Label 'Signed Nexo catalog response'
  if ($success -isnot [bool] -or -not $success) { throw 'The signed Nexo catalog endpoint did not report success.' }
  $data = Get-DreamSkinSignedNexoExactProperty -Value $wrapper -Name 'data' -Label 'Signed Nexo catalog response'
  Assert-DreamSkinSignedNexoExactKeys -Value $data -Label 'Signed Nexo catalog envelope' `
    -Expected @('keyId', 'payloadBase64', 'signatureBase64')
  return ($data | ConvertTo-Json -Compress)
}

function Resolve-DreamSkinSignedNexoSkin {
  param(
    [Parameter(Mandatory = $true)][string]$SkinId,
    [string]$StateRoot = (Join-Path $env:LOCALAPPDATA 'CodexDreamSkin'),
    [hashtable]$PublicKeys = $script:DreamSkinSignedNexoPublicKeys,
    [datetime]$Now = [datetime]::UtcNow,
    [switch]$SkipRefresh
  )
  if (-not (Test-DreamSkinSignedNexoId -Value $SkinId)) { throw 'The requested signed Nexo skin id is invalid.' }
  $catalog = $null
  if (-not $SkipRefresh) {
    try {
      $catalog = Import-DreamSkinSignedNexoCatalogEnvelope `
        -EnvelopeJson (Get-DreamSkinSignedNexoRemoteEnvelope) -StateRoot $StateRoot `
        -PublicKeys $PublicKeys -Now $Now
    } catch {
      try {
        $catalog = Read-DreamSkinSignedNexoCatalogCache `
          -StateRoot $StateRoot -PublicKeys $PublicKeys -Now $Now
      } catch { throw $_ }
    }
  } else {
    $catalog = Read-DreamSkinSignedNexoCatalogCache `
      -StateRoot $StateRoot -PublicKeys $PublicKeys -Now $Now
  }
  if (@($catalog.Revocations) -ccontains $SkinId) {
    $errorRecord = [InvalidOperationException]::new('The requested signed Nexo skin has been revoked.')
    $errorRecord.Data['DreamSkinNexoCatalogResult'] = 'Revoked'
    throw $errorRecord
  }
  if ($catalog.IsStale) {
    $errorRecord = [InvalidOperationException]::new(
      'The last-known-good signed Nexo catalog is stale and cannot add remote-only skins.'
    )
    $errorRecord.Data['DreamSkinNexoCatalogResult'] = 'Stale'
    throw $errorRecord
  }
  $matches = @($catalog.Skins | Where-Object { $_.Id -ceq $SkinId })
  if ($matches.Count -ne 1) {
    $errorRecord = [InvalidOperationException]::new('The requested skin is not in the verified signed Nexo catalog.')
    $errorRecord.Data['DreamSkinNexoCatalogResult'] = 'Unknown'
    throw $errorRecord
  }
  $skin = $matches[0]
  return [pscustomobject]@{
    Id = $skin.Id
    Name = $skin.NameZh
    NameEn = $skin.NameEn
    Appearance = $skin.Appearance
    ImageUri = $catalog.AssetOrigin + $skin.BackgroundPath
    BackgroundSha256 = $skin.BackgroundSha256
    PreviewUri = $catalog.AssetOrigin + $skin.PreviewPath
    PreviewSha256 = $skin.PreviewSha256
    CatalogVersion = $catalog.CatalogVersion
  }
}
