import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const macos = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const root = path.resolve(macos, "..");
const read = (relative) => fs.readFileSync(path.join(root, relative), "utf8");

test("macOS schedules a throttled startup update check and packages a detached updater", () => {
  const app = read("macos/menubar-app/Sources/CodexDreamSkinMenuBar/AppDelegate.swift");
  const builder = read("macos/scripts/build-menubar-app.sh");
  const updater = read("macos/scripts/install-update-macos.sh");
  assert.match(app, /scheduleAutomaticUpdateCheck\(\)/);
  assert.match(app, /24 \* 60 \* 60/);
  assert.match(app, /NexoSkinContract\.isCanonicalApplyURL/);
  assert.match(app, /launchVerifiedUpdate/);
  assert.match(app, /arguments: \["--json", "--current-version", appVersion\]/);
  assert.match(app, /releaseNotesBase64/);
  assert.match(app, /更新说明/);
  assert.match(builder, /install-update-macos\.sh/);
  assert.match(updater, /CodexDreamSkin-v\$VERSION\.dmg/);
  assert.match(updater, /SHA256SUMS\.txt/);
  assert.match(updater, /shasum -a 256/);
  assert.match(updater, /cc\.dreamskin\.menubar/);
  assert.doesNotMatch(updater, /killall .*Codex|pkill .*Codex|com\.openai\.codex/);
  assert.match(app, /completeDeferredEngineUpdateIfPossible\(\)/);
  assert.match(app, /更新已就绪，关闭 ChatGPT 后自动完成/);
  assert.match(app, /if installedScript\(named: "status-dream-skin-macos\.sh"\) == nil/);
});

test("macOS update checker accepts the signed app version and returns safe release notes", () => {
  const checker = read("macos/scripts/check-update-macos.sh");
  assert.match(checker, /--current-version/);
  assert.match(checker, /CURRENT_OVERRIDE/);
  assert.match(checker, /releaseNotesBase64/);
  assert.match(checker, /base64/);
});

test("release packaging does not repeat the full Windows matrix", () => {
  const workflow = read(".github/workflows/release.yml");
  const buildWindows = workflow.slice(
    workflow.indexOf("  build-windows:"),
    workflow.indexOf("  publish-release:")
  );
  assert.doesNotMatch(buildWindows, /windows\\tests\\run-tests\.ps1/);
  assert.match(buildWindows, /windows\\tests\\installer-static\.tests\.ps1/);
  assert.match(buildWindows, /NodeArchivePath/);
});

test("Windows stages verified updates and waits for Codex to close naturally", () => {
  const checker = read("windows/scripts/check-update.ps1");
  const tray = read("windows/scripts/tray-dream-skin.ps1");
  const handler = read("windows/scripts/apply-community-theme.ps1");
  assert.match(checker, /\[switch\]\$Auto/);
  assert.match(checker, /\[switch\]\$InstallPending/);
  assert.match(checker, /CodexDreamSkin-Setup-v\$LatestVersion\.exe/);
  assert.match(checker, /SHA256SUMS\.txt/);
  assert.match(checker, /Get-FileHash .*SHA256/);
  assert.match(checker, /pending-update\.json/);
  assert.match(tray, /-Auto/);
  assert.match(tray, /-InstallPending/);
  assert.match(handler, /Test-DreamSkinNexoApplyUri/);
  assert.doesNotMatch(checker, /Stop-Process[^\n]*Codex|taskkill[^\n]*Codex/i);
});
