import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const read = (relative) => fs.readFileSync(path.join(root, relative), "utf8");

test("macOS and Windows expose the Nexo product brand", () => {
  const surfaces = [
    "macos/menubar-app/Sources/CodexDreamSkinMenuBar/AppDelegate.swift",
    "macos/menubar-app/Resources/Info.plist.template",
    "macos/scripts/check-update-macos.sh",
    "windows/scripts/tray-dream-skin.ps1",
    "windows/scripts/check-update.ps1",
    "windows/installer/setup-bootstrap.ps1",
    "windows/installer/codex-dream-skin.iss",
  ].map(read).join("\n");

  assert.match(surfaces, /Nexo Codex Skin/);
  assert.doesNotMatch(surfaces, /打开 DreamSkin\.cc|主题库 Gallery|在线 Studio/);
  assert.match(read("windows/installer/codex-dream-skin.iss"), /#define AppPublisher "NexoToken"/);
  assert.match(read("windows/installer/codex-dream-skin.iss"), /#define AppUrl "https:\/\/nexotoken\.net"/);
});

test("both clients use the Nexo concentric-ring mark", () => {
  const macIcon = read("macos/menubar-app/Tools/generate-icon.swift");
  const windowsIcon = read("windows/installer/build-release.ps1");
  const menu = read("macos/menubar-app/Sources/CodexDreamSkinMenuBar/AppDelegate.swift");

  assert.match(macIcon, /Nexo concentric-ring mark/);
  assert.match(macIcon, /0\.5725, green: 0\.9961, blue: 0\.6157/);
  assert.match(macIcon, /0\.0000, green: 0\.7882, blue: 1\.0000/);
  assert.match(windowsIcon, /Nexo concentric-ring mark/);
  assert.match(menu, /Nexo 同心环模板图标/);
});

test("advanced tools are collapsed without breaking upgrade identity", () => {
  const mac = read("macos/menubar-app/Sources/CodexDreamSkinMenuBar/AppDelegate.swift");
  const windows = read("windows/scripts/tray-dream-skin.ps1");
  const installer = read("windows/installer/codex-dream-skin.iss");

  assert.match(mac, /NSMenuItem\(title: "高级工具"/);
  assert.match(windows, /ToolStripMenuItem\]::new\('高级工具'\)/);
  assert.match(installer, /AppId=\{\{DCCDAF1A-9ACD-4AAB-B55B-DF17EB2CDA2E\}/);
  assert.match(installer, /Software\\Classes\\dreamskin/);
  assert.match(installer, /\[InstallDelete\][\s\S]*Codex Dream Skin\.lnk/);
});
