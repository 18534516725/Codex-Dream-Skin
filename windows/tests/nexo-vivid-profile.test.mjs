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
const catalog = JSON.parse(await fs.readFile(path.join(root, "assets/nexo-skin-catalog.json"), "utf8"));
const publication = JSON.parse(await fs.readFile(path.join(root, "../themes/platform-publication-catalog.json"), "utf8"));

assert.equal(catalog.schemaVersion, 2);
assert.equal(catalog.items.length, 124);
assert.deepEqual(
  catalog.items.map((item) => [item.id, item.assetFile]),
  publication.items.map((item) => [item.id, path.basename(item.assetUrl)]),
);
assert.ok(catalog.items.every((item) => ["dark", "light"].includes(item.theme.appearance)));
assert.ok(catalog.items.every((item) => item.theme.art.taskMode === "full"));
for (const field of [
  "AccentRGB", "SecondaryRGB", "PanelRGB", "GlowStrength", "Signature", "FocusX", "FocusY",
  "LayoutVariant", "SurfaceStyle", "CornerStyle", "MotionPreset", "SidebarStyle", "ComposerStyle", "TextureStyle",
]) {
  assert.match(themeContract, new RegExp(`${field}\\s*=`), `Windows fixed skin profiles must expose ${field}`);
}
assert.doesNotMatch(themeContract, /DreamSkinNexoCatalog\s*=\s*@\{/);
for (const id of [
  "post-raccoon", "night-shift-penguin", "workshop-otter",
  "moon-platform-cat", "floppy-wizard", "deep-sea-repair",
]) {
  assert.ok(catalog.items.some((item) => item.id === id), `Windows must expose ${id}`);
}
assert.match(
  applyScript,
  /Set-DreamSkinActiveTheme[^\r\n]*-Theme\s+\$themeProfile/,
  "Windows must pass the fixed skin profile into theme generation",
);
assert.match(themeContract, /LayoutVariant\s*=\s*\[string\]\$record\.theme\.visual\.layout[\s\S]*SurfaceStyle\s*=\s*\[string\]\$record\.theme\.visual\.surface[\s\S]*CornerStyle\s*=\s*\[string\]\$record\.theme\.visual\.corners[\s\S]*MotionPreset\s*=\s*\[string\]\$record\.theme\.visual\.motion[\s\S]*SidebarStyle\s*=\s*\[string\]\$record\.theme\.visual\.sidebar[\s\S]*ComposerStyle\s*=\s*\[string\]\$record\.theme\.visual\.composer[\s\S]*TextureStyle\s*=\s*\[string\]\$record\.theme\.visual\.texture/, "Windows resolver must return every deep visual field");
assert.match(applyScript, /visual\s*=\s*\[pscustomobject\]@\{[\s\S]*accentRGB[\s\S]*secondaryRGB[\s\S]*panelRGB[\s\S]*glowStrength[\s\S]*signature[\s\S]*layoutVariant[\s\S]*surfaceStyle[\s\S]*cornerStyle[\s\S]*motionPreset[\s\S]*sidebarStyle[\s\S]*composerStyle[\s\S]*textureStyle[\s\S]*\}/, "Windows must serialize the complete deep visual profile");

console.log("Windows Nexo vivid profile tests passed");
