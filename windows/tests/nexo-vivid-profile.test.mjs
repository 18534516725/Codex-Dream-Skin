import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const [themeContract, applyScript] = await Promise.all([
  fs.readFile(path.join(root, "scripts/theme-windows.ps1"), "utf8"),
  fs.readFile(path.join(root, "scripts/apply-community-theme.ps1"), "utf8"),
]);

assert.match(themeContract, /Appearance\s*=\s*'dark'/, "fixed Windows skins must use dark native chrome");
assert.match(themeContract, /TaskMode\s*=\s*'full'/, "fixed Windows skins must use full-strength artwork");
for (const field of [
  "AccentRGB", "SecondaryRGB", "PanelRGB", "GlowStrength", "Signature", "FocusX", "FocusY",
  "LayoutVariant", "SurfaceStyle", "CornerStyle", "MotionPreset", "SidebarStyle", "ComposerStyle", "TextureStyle",
]) {
  assert.match(themeContract, new RegExp(`${field}\\s*=`), `Windows fixed skin profiles must expose ${field}`);
}
assert.equal(
  [...themeContract.matchAll(/^\s*'[a-z0-9-]+'\s*=\s*@\{/gm)].length,
  18,
  "Windows must define one visual profile for each of the 18 fixed skins",
);
for (const id of [
  "post-raccoon", "night-shift-penguin", "workshop-otter",
  "moon-platform-cat", "floppy-wizard", "deep-sea-repair",
]) {
  assert.match(themeContract, new RegExp(`'${id}'\\s*=`), `Windows must expose ${id}`);
}
assert.match(
  applyScript,
  /Set-DreamSkinActiveTheme[^\r\n]*-Theme\s+\$themeProfile/,
  "Windows must pass the fixed skin profile into theme generation",
);
assert.match(applyScript, /visual\s*=\s*\[pscustomobject\]@\{[\s\S]*accentRGB[\s\S]*secondaryRGB[\s\S]*panelRGB[\s\S]*glowStrength[\s\S]*signature[\s\S]*\}/, "Windows must serialize the complete visual profile");

console.log("Windows Nexo vivid profile tests passed");
