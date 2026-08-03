import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const [macMenu, windowsTray] = await Promise.all([
  fs.readFile(path.join(root, "macos/menubar-app/Sources/CodexDreamSkinMenuBar/AppDelegate.swift"), "utf8"),
  fs.readFile(path.join(root, "windows/scripts/tray-dream-skin.ps1"), "utf8"),
]);

for (const [platform, source] of [["macOS", macMenu], ["Windows", windowsTray]]) {
  assert.doesNotMatch(source, /主题库 Gallery/, `${platform} must not expose a public theme-gallery shortcut`);
  assert.doesNotMatch(source, /在线 Studio/, `${platform} must not expose the external online Studio shortcut`);
  assert.doesNotMatch(source, /打开 DreamSkin\.cc/, `${platform} must not expose the upstream website shortcut`);
}

assert.doesNotMatch(macMenu, /openThemeGallery|openOnlineStudio|openDreamSkinWebsite/);
assert.doesNotMatch(windowsTray, /Start-Process -FilePath 'https:\/\/dreamskin\.cc(?:\/gallery|\/studio)?'/);

console.log("Paid distribution boundary tests passed");
