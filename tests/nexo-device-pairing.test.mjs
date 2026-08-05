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

test('macOS verifies entitlement before downloading and reports the bound request outcome', () => {
  const verify = macApp.indexOf('verifyEntitlement(skinID: entry.id)');
  const download = macApp.indexOf('communityHTTP.get(', verify);
  assert.ok(verify >= 0 && download > verify);
  assert.match(macApp, /reportOutcome\(\s*requestID: authorization\.requestID,\s*status: \.succeeded/);
  assert.match(macApp, /reportOutcome\(\s*requestID: authorization\.requestID,\s*status: \.failed/);
  assert.match(macApp, /SHA256\.hash\(data: payload\.body\)/);
  assert.match(macApp, /if let expectedHash = entry\.backgroundSha256/);
  assert.match(macApp, /addButton\(withTitle: "取消"\)[\s\S]{0,180}alertSecondButtonReturn/);
  assert.match(macApp, /refreshSignedNexoCatalog\(\)/);
  assert.match(macApp, /beginNexoPairing/);
  const pairingAction = macApp.indexOf('private func beginNexoPairing');
  const statusCheck = macApp.indexOf('currentPairingStatus', pairingAction);
  const pairingStart = macApp.indexOf('startPairing', pairingAction);
  assert.ok(statusCheck >= 0 && pairingStart > statusCheck);
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

test('Windows Nexo apply verifies before asset download and reports a closed set of outcomes', () => {
  const start = windowsApply.indexOf('function Invoke-DreamSkinNexoApply');
  const end = windowsApply.indexOf('function New-DreamSkinCommunityHttpRequest', start);
  const nexoApply = windowsApply.slice(start, end);
  const verify = nexoApply.indexOf('Invoke-DreamSkinNexoEntitlementVerification');
  const download = nexoApply.indexOf('WebRequest]::Create', verify);
  assert.ok(verify >= 0 && download > verify);
  assert.match(nexoApply, /Send-DreamSkinNexoApplyOutcome[^\n]+-Status 'succeeded'/);
  assert.match(nexoApply, /Send-DreamSkinNexoApplyOutcome[^\n]+-Status 'failed'/);
  assert.match(nexoApply, /Get-FileHash[^\n]+SHA256/);
  assert.match(nexoApply, /-PromptRestart/);
  assert.doesNotMatch(nexoApply, /-RestartExisting|Stop-DreamSkinCodex/);
});

test('Windows tray exposes pairing without credentials or restart flags', () => {
  assert.match(windowsTray, /连接 NexoToken 账号/);
  assert.match(windowsTray, /Ensure-DreamSkinNexoPairing/);
  assert.doesNotMatch(windowsTray, /Authorization|Bearer|accessToken|refreshToken/);
});
