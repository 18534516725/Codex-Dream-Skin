Set-StrictMode -Version 2.0

$script:DreamSkinNexoApiRoot = 'https://nexotoken.net/api/codex-skin-devices'
$script:DreamSkinNexoCredentialTarget = 'NexoToken/CodexDreamSkin/Ed25519-v1'
$script:DreamSkinNexoMaximumResponseBytes = 65536
$script:DreamSkinNexoMaximumPairingPolls = 300

if (-not ('DreamSkinCredentialManager' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DreamSkinCredentialManager {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  private struct CREDENTIAL {
    public UInt32 Flags; public UInt32 Type; public string TargetName;
    public string Comment; public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
    public UInt32 CredentialBlobSize; public IntPtr CredentialBlob; public UInt32 Persist;
    public UInt32 AttributeCount; public IntPtr Attributes; public string TargetAlias;
    public string UserName;
  }
  [DllImport("advapi32.dll", EntryPoint="CredWriteW", CharSet=CharSet.Unicode, SetLastError=true)]
  private static extern bool CredWrite(ref CREDENTIAL credential, UInt32 flags);
  [DllImport("advapi32.dll", EntryPoint="CredReadW", CharSet=CharSet.Unicode, SetLastError=true)]
  private static extern bool CredRead(string target, UInt32 type, UInt32 flags, out IntPtr credential);
  [DllImport("advapi32.dll", EntryPoint="CredFree", SetLastError=true)]
  private static extern void CredFree(IntPtr credential);
  public static string Read(string target) {
    IntPtr pointer;
    if (!CredRead(target, 1, 0, out pointer)) return null;
    try {
      CREDENTIAL value = (CREDENTIAL)Marshal.PtrToStructure(pointer, typeof(CREDENTIAL));
      if (value.CredentialBlob == IntPtr.Zero || value.CredentialBlobSize == 0) return null;
      return Marshal.PtrToStringUni(value.CredentialBlob, checked((int)value.CredentialBlobSize / 2));
    } finally { CredFree(pointer); }
  }
  public static void Write(string target, string secret) {
    if (String.IsNullOrEmpty(secret) || secret.Length > 240) throw new ArgumentException("credential size");
    IntPtr blob = Marshal.StringToCoTaskMemUni(secret);
    try {
      CREDENTIAL value = new CREDENTIAL(); value.Type = 1; value.TargetName = target;
      value.CredentialBlobSize = checked((UInt32)(secret.Length * 2)); value.CredentialBlob = blob;
      value.Persist = 2; value.UserName = "CodexDreamSkinDevice";
      if (!CredWrite(ref value, 0)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    } finally { Marshal.FreeCoTaskMem(blob); }
  }
}
'@
}

function Invoke-DreamSkinNexoNodeJson {
  param(
    [Parameter(Mandatory = $true)][string]$JavaScript,
    [AllowEmptyString()][string]$StandardInput = ''
  )
  $node = Get-DreamSkinNodeRuntime
  $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($JavaScript))
  $process = [Diagnostics.Process]::new()
  $process.StartInfo.FileName = $node.Path
  $process.StartInfo.Arguments = "-e `"eval(Buffer.from('$encoded','base64').toString('utf8'))`""
  $process.StartInfo.UseShellExecute = $false
  $process.StartInfo.CreateNoWindow = $true
  $process.StartInfo.RedirectStandardInput = $true
  $process.StartInfo.RedirectStandardOutput = $true
  $process.StartInfo.RedirectStandardError = $true
  if (-not $process.Start()) { throw 'Could not start the device cryptography runtime.' }
  try {
    $process.StandardInput.Write($StandardInput)
    $process.StandardInput.Close()
    $output = $process.StandardOutput.ReadToEnd()
    $null = $process.StandardError.ReadToEnd()
    if (-not $process.WaitForExit(10000) -or $process.ExitCode -ne 0 -or $output.Length -gt 4096) {
      try { $process.Kill() } catch {}
      throw 'The device cryptography operation failed.'
    }
    return $output | ConvertFrom-Json
  } finally { $process.Dispose() }
}

function Get-DreamSkinNexoDeviceIdentity {
  $stored = [DreamSkinCredentialManager]::Read($script:DreamSkinNexoCredentialTarget)
  if ($stored) {
    try {
      $identity = $stored | ConvertFrom-Json
      if ("$($identity.installationId)" -cmatch '\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z' -and
        "$($identity.publicKeyBase64)" -cmatch '\A[A-Za-z0-9+/]{43}=\z' -and
        -not [string]::IsNullOrWhiteSpace("$($identity.privateKeyBase64)")) { return $identity }
    } catch {}
    throw 'The saved device identity is invalid.'
  }
  $generated = Invoke-DreamSkinNexoNodeJson -JavaScript @'
const {generateKeyPairSync}=require('crypto');
const {publicKey,privateKey}=generateKeyPairSync('ed25519');
const spki=publicKey.export({format:'der',type:'spki'});
process.stdout.write(JSON.stringify({publicKeyBase64:spki.subarray(spki.length-32).toString('base64'),privateKeyBase64:privateKey.export({format:'der',type:'pkcs8'}).toString('base64')}));
'@
  $identity = [ordered]@{
    installationId = [guid]::NewGuid().ToString('D').ToLowerInvariant()
    publicKeyBase64 = "$($generated.publicKeyBase64)"
    privateKeyBase64 = "$($generated.privateKeyBase64)"
  }
  $serialized = $identity | ConvertTo-Json -Compress
  [DreamSkinCredentialManager]::Write($script:DreamSkinNexoCredentialTarget, $serialized)
  return [pscustomobject]$identity
}

function ConvertTo-DreamSkinJsonString {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)
  Add-Type -AssemblyName System.Web.Extensions -ErrorAction Stop
  return ([Web.Script.Serialization.JavaScriptSerializer]::new()).Serialize($Value)
}

function ConvertTo-DreamSkinCanonicalJson {
  param([Parameter(Mandatory = $true)][AllowNull()]$Value)
  if ($null -eq $Value) { return 'null' }
  if ($Value -is [string]) { return ConvertTo-DreamSkinJsonString -Value $Value }
  if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }
  if ($Value -is [Collections.IDictionary] -or $Value -is [pscustomobject]) {
    $dictionary = @{}
    if ($Value -is [Collections.IDictionary]) {
      foreach ($key in $Value.Keys) { $dictionary["$key"] = $Value[$key] }
    } else {
      foreach ($property in $Value.PSObject.Properties) { $dictionary[$property.Name] = $property.Value }
    }
    $pairs = foreach ($key in @($dictionary.Keys | Sort-Object)) {
      (ConvertTo-DreamSkinJsonString -Value $key) + ':' + (ConvertTo-DreamSkinCanonicalJson -Value $dictionary[$key])
    }
    return '{' + ($pairs -join ',') + '}'
  }
  if ($Value -is [Collections.IEnumerable]) {
    return '[' + (@($Value | ForEach-Object { ConvertTo-DreamSkinCanonicalJson -Value $_ }) -join ',') + ']'
  }
  return [Convert]::ToString($Value, [Globalization.CultureInfo]::InvariantCulture)
}

function New-DreamSkinNexoSignedEnvelope {
  param([Parameter(Mandatory = $true)][Collections.IDictionary]$Body)
  $identity = Get-DreamSkinNexoDeviceIdentity
  $random = New-Object byte[] 18
  [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($random)
  $nonce = [Convert]::ToBase64String($random).TrimEnd('=').Replace('+', '-').Replace('/', '_')
  $unsigned = [ordered]@{
    body = $Body
    installationId = "$($identity.installationId)"
    nonce = $nonce
    timestamp = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", [Globalization.CultureInfo]::InvariantCulture)
  }
  $canonical = ConvertTo-DreamSkinCanonicalJson -Value $unsigned
  $signInput = @{ privateKeyBase64 = "$($identity.privateKeyBase64)"; payloadBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($canonical)) } | ConvertTo-Json -Compress
  $signed = Invoke-DreamSkinNexoNodeJson -StandardInput $signInput -JavaScript @'
const {createPrivateKey,sign}=require('crypto');let s='';process.stdin.setEncoding('utf8');process.stdin.on('data',x=>s+=x);process.stdin.on('end',()=>{const x=JSON.parse(s);const k=createPrivateKey({key:Buffer.from(x.privateKeyBase64,'base64'),format:'der',type:'pkcs8'});process.stdout.write(JSON.stringify({signatureBase64:sign(null,Buffer.from(x.payloadBase64,'base64'),k).toString('base64')}));});
'@
  $unsigned['signatureBase64'] = "$($signed.signatureBase64)"
  return $unsigned
}

function Invoke-DreamSkinNexoApi {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST')][string]$Method,
    [Parameter(Mandatory = $true)][string]$Path,
    [AllowNull()]$Body = $null
  )
  if ($Path -cnotmatch '\A(?:pairing/start|pairing/[0-9a-f-]{36}|verify-entitlement|apply-outcomes)\z') {
    throw 'The device API path is not allowed.'
  }
  $uri = "$script:DreamSkinNexoApiRoot/$Path"
  $request = [Net.HttpWebRequest][Net.WebRequest]::Create([Uri]::new($uri, [UriKind]::Absolute))
  $request.Method = $Method; $request.Accept = 'application/json'; $request.ContentType = 'application/json'
  $request.UserAgent = 'CodexDreamSkin/device-v1'; $request.AllowAutoRedirect = $false
  $request.Timeout = 15000; $request.ReadWriteTimeout = 15000
  if ($null -ne $Body) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Compress -Depth 8))
    $request.ContentLength = $bytes.Length
    $stream = $request.GetRequestStream(); try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
  }
  $response = $request.GetResponse()
  try {
    if ($response.ResponseUri.AbsoluteUri -cne $uri -or [int]$response.StatusCode -notin @(200, 201) -or
      $response.ContentLength -gt $script:DreamSkinNexoMaximumResponseBytes) { throw 'The device API returned an invalid response.' }
    $input = $response.GetResponseStream(); $memory = [IO.MemoryStream]::new()
    try {
      $buffer = New-Object byte[] 4096
      while (($read = $input.Read($buffer, 0, $buffer.Length)) -gt 0) {
        if ($memory.Length + $read -gt $script:DreamSkinNexoMaximumResponseBytes) { throw 'The device API response was too large.' }
        $memory.Write($buffer, 0, $read)
      }
      $parsed = ([Text.UTF8Encoding]::new($false, $true)).GetString($memory.ToArray()) | ConvertFrom-Json
    } finally { $memory.Dispose(); $input.Dispose() }
    if ($parsed.success -ne $true -or $null -eq $parsed.data) { throw 'The device API rejected the request.' }
    return $parsed.data
  } finally { $response.Dispose() }
}

function Ensure-DreamSkinNexoPairing {
  $identity = Get-DreamSkinNexoDeviceIdentity
  $status = Invoke-DreamSkinNexoApi -Method GET -Path "pairing/$($identity.installationId)"
  if ("$($status.status)" -ceq 'active') { return }
  $challenge = Invoke-DreamSkinNexoApi -Method POST -Path 'pairing/start' -Body ([ordered]@{
    installationId = "$($identity.installationId)"; platform = 'windows'; publicKeyBase64 = "$($identity.publicKeyBase64)"
  })
  if ("$($challenge.pairingCode)" -cnotmatch '\A[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}\z' -or
    "$($challenge.expiresAt)" -cnotmatch '\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z\z') {
    throw 'The device API returned an invalid pairing challenge.'
  }
  Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
  $choice = [Windows.Forms.MessageBox]::Show(
    "连接码：$($challenge.pairingCode)`r`n`r`n请在 NexoToken 的 Codex 皮肤页面确认。助手不会读取或保存你的登录令牌。",
    '连接 NexoToken 账号', [Windows.Forms.MessageBoxButtons]::OKCancel,
    [Windows.Forms.MessageBoxIcon]::Information, [Windows.Forms.MessageBoxDefaultButton]::Button2
  )
  if ($choice -ne [Windows.Forms.DialogResult]::OK) { throw 'Account pairing was cancelled.' }
  Start-Process -FilePath 'https://nexotoken.net/?view=codex-skins' | Out-Null
  for ($attempt = 0; $attempt -lt $script:DreamSkinNexoMaximumPairingPolls; $attempt++) {
    Start-Sleep -Seconds 2
    $status = Invoke-DreamSkinNexoApi -Method GET -Path "pairing/$($identity.installationId)"
    if ("$($status.status)" -ceq 'active') { return }
    if ("$($status.status)" -cne 'pairing') { break }
  }
  throw 'Account pairing expired.'
}

function Invoke-DreamSkinNexoEntitlementVerification {
  param([Parameter(Mandatory = $true)][string]$SkinId)
  if ($SkinId -cnotmatch '\A[a-z0-9]+(?:-[a-z0-9]+)*\z' -or $SkinId.Length -gt 64) { throw 'Invalid skin ID.' }
  Ensure-DreamSkinNexoPairing
  $envelope = New-DreamSkinNexoSignedEnvelope -Body ([ordered]@{ action = 'verify'; skinId = $SkinId })
  $result = Invoke-DreamSkinNexoApi -Method POST -Path 'verify-entitlement' -Body $envelope
  if ($result.allowed -ne $true -or "$($result.requestId)" -cnotmatch '\A[A-Za-z0-9-]{1,64}\z') {
    throw 'The connected account is not entitled to this skin.'
  }
  return [pscustomobject]@{ RequestId = "$($result.requestId)" }
}

function Send-DreamSkinNexoApplyOutcome {
  param(
    [Parameter(Mandatory = $true)][string]$RequestId,
    [Parameter(Mandatory = $true)][ValidateSet('succeeded', 'failed')][string]$Status,
    [ValidateSet('', 'CODEX_NOT_FOUND', 'HELPER_UPDATE_REQUIRED', 'THEME_APPLY_FAILED', 'RENDER_VERIFICATION_FAILED', 'SKIN_ASSET_UNAVAILABLE', 'SKIN_NOT_SUPPORTED')][string]$FailureCode = ''
  )
  if ($RequestId -cnotmatch '\A[A-Za-z0-9-]{1,64}\z' -or ($Status -ceq 'failed' -and -not $FailureCode) -or
    ($Status -ceq 'succeeded' -and $FailureCode)) { return $false }
  $body = [ordered]@{ action = 'report'; requestId = $RequestId; status = $Status }
  if ($FailureCode) { $body['failureCode'] = $FailureCode }
  try {
    $envelope = New-DreamSkinNexoSignedEnvelope -Body $body
    $null = Invoke-DreamSkinNexoApi -Method POST -Path 'apply-outcomes' -Body $envelope
    return $true
  } catch { return $false }
}
