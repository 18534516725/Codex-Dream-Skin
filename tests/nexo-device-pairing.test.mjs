import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const root = new URL('../', import.meta.url);
const macDevice = readFileSync(new URL('macos/menubar-app/Sources/CodexDreamSkinMenuBar/NexoDeviceClient.swift', root), 'utf8');
const macApp = readFileSync(new URL('macos/menubar-app/Sources/CodexDreamSkinMenuBar/AppDelegate.swift', root), 'utf8');
const windowsDevice = readFileSync(new URL('windows/scripts/nexo-device.ps1', root), 'utf8');
const windowsApply = readFileSync(new URL('windows/scripts/apply-community-theme.ps1', root), 'utf8');
const windowsTray = readFileSync(new URL('windows/scripts/tray-dream-skin.ps1', root), 'utf8');

test('macOS keeps its Ed25519 device identity in private application support storage', () => {
  assert.match(macDevice, /Curve25519\.Signing\.PrivateKey/);
  assert.match(macDevice, /device-identity\.json/);
  assert.match(macDevice, /fchmod\(descriptor, 0o700\)/);
  assert.match(macDevice, /fchmod\(descriptor, 0o600\)/);
  assert.doesNotMatch(macDevice, /import Security|SecItem|kSec/);
  assert.match(macDevice, /URLSessionConfiguration\.ephemeral/);
  assert.match(macDevice, /https:\/\/nexotoken\.net\/api\/codex-skin-devices/);
  assert.match(macDevice, /maximumPairingPolls\s*=\s*300/);
  assert.doesNotMatch(macDevice, /Authorization|Bearer|accessToken|refreshToken/);
});

test('macOS downloads approved skins locally without account pairing or entitlement checks', () => {
  const download = macApp.indexOf('communityHTTP.get(');
  assert.ok(download >= 0);
  assert.doesNotMatch(macApp, /verifyEntitlement|reportOutcome|beginNexoPairing|currentPairingStatus/);
  assert.match(macApp, /SHA256\.hash\(data: payload\.body\)/);
  assert.match(macApp, /if let expectedHash = entry\.backgroundSha256/);
  assert.match(macApp, /addButton\(withTitle: "取消"\)[\s\S]{0,180}alertSecondButtonReturn/);
  assert.match(macApp, /refreshSignedNexoCatalog\(\)/);
});

test('Windows stores its Ed25519 identity in Credential Manager and signs canonical envelopes', () => {
  assert.match(windowsDevice, /CredWriteW/);
  assert.match(windowsDevice, /generateKeyPairSync\('ed25519'\)/);
  assert.match(windowsDevice, /https:\/\/nexotoken\.net\/api\/codex-skin-devices/);
  assert.match(windowsDevice, /ConvertTo-DreamSkinCanonicalJson/);
  assert.match(windowsDevice, /Invoke-DreamSkinNexoEntitlementVerification/);
  assert.match(windowsDevice, /Send-DreamSkinNexoApplyOutcome/);
  assert.doesNotMatch(windowsDevice, /Authorization|Bearer|accessToken|refreshToken/);
});

test('Windows Nexo apply downloads approved skins locally without account checks', () => {
  const start = windowsApply.indexOf('function Invoke-DreamSkinNexoApply');
  const end = windowsApply.indexOf('function New-DreamSkinCommunityHttpRequest', start);
  const nexoApply = windowsApply.slice(start, end);
  assert.doesNotMatch(nexoApply, /Invoke-DreamSkinNexoEntitlementVerification|Send-DreamSkinNexoApplyOutcome|Ensure-DreamSkinNexoPairing/);
  assert.ok(nexoApply.indexOf('WebRequest]::Create') >= 0);
  assert.match(nexoApply, /Get-FileHash[^\n]+SHA256/);
  assert.match(nexoApply, /-PromptRestart/);
  assert.doesNotMatch(nexoApply, /-RestartExisting|Stop-DreamSkinCodex/);
});

test('Windows tray does not expose account pairing', () => {
  assert.doesNotMatch(windowsTray, /连接 NexoToken 账号/);
  assert.doesNotMatch(windowsTray, /Ensure-DreamSkinNexoPairing/);
  assert.doesNotMatch(windowsTray, /Authorization|Bearer|accessToken|refreshToken/);
});
