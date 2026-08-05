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
  assert.match(updater, /--retry 3/,
    "transient GitHub failures must be retried before abandoning an update");
  assert.doesNotMatch(updater, /--retry-all-errors/,
    "the updater must remain compatible with the curl bundled by older supported macOS releases");
  assert.match(updater, /reopen_current_app_on_failure/);
  assert.match(updater, /\/usr\/bin\/open "\$TARGET_APP"/,
    "a failed detached update must restore the still-valid installed helper");
  assert.match(updater, /hdiutil detach "\$MOUNT"/,
    "cleanup must detach by mount point even when macOS canonicalizes \/tmp to \/private\/tmp");
  assert.doesNotMatch(updater, /mount \| .*grep.*\$MOUNT/,
    "cleanup must not compare non-canonical mount path strings");
  assert.doesNotMatch(updater, /killall .*Codex|pkill .*Codex|com\.openai\.codex/);
  assert.match(app, /completeDeferredEngineUpdateIfPossible\(\)/);
  assert.match(app, /更新已就绪，关闭 ChatGPT 后自动完成/);
  assert.match(app, /waitingForCodexExitToInstallEngine/,
    "a clean install must wait for Codex to close instead of failing");
  assert.match(app, /continueDeferredEngineInstallIfPossible\(\)/);
  assert.match(app, /首次安装需要退出 Codex/);
  assert.match(app, /正常退出 Codex 后，助手会自动完成组件安装/);
  assert.doesNotMatch(app, /terminateApplication|forceTerminate|killall.*Codex|pkill.*Codex/,
    "the helper must never force-close Codex");
  assert.match(app, /if installedScript\(named: "status-dream-skin-macos\.sh"\) == nil/);
  assert.match(app, /换肤组件会在你自然关闭 Codex 后自动升级/,
    "the updater must explain that the running engine is deferred without closing Codex");
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
