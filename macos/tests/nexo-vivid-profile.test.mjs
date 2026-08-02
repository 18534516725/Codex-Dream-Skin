import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const [contract, appDelegate, loader, writer] = await Promise.all([
  fs.readFile(path.join(root, "menubar-app/Sources/DreamSkinCore/NexoSkinLink.swift"), "utf8"),
  fs.readFile(path.join(root, "menubar-app/Sources/CodexDreamSkinMenuBar/AppDelegate.swift"), "utf8"),
  fs.readFile(path.join(root, "scripts/load-image-theme-macos.sh"), "utf8"),
  fs.readFile(path.join(root, "scripts/write-theme.mjs"), "utf8"),
]);

for (const field of [
  "accentRGB", "secondaryRGB", "panelRGB", "glowStrength", "signature", "focusX", "focusY",
  "layoutVariant", "surfaceStyle", "cornerStyle", "motionPreset", "sidebarStyle", "composerStyle", "textureStyle",
]) {
  assert.match(contract, new RegExp(`public let ${field}:`), `macOS fixed skin profiles must expose ${field}`);
}
assert.equal(
  [...contract.matchAll(/^\s*"[a-z0-9-]+":\s*\.init\(/gm)].length,
  18,
  "macOS must define one visual profile for each of the 18 fixed skins",
);
for (const id of [
  "post-raccoon", "night-shift-penguin", "workshop-otter",
  "moon-platform-cat", "floppy-wizard", "deep-sea-repair",
]) {
  assert.match(contract, new RegExp(`"${id}"`), `macOS must expose ${id}`);
}

assert.match(
  appDelegate,
  /arguments:\s*\[[^\]]*"--appearance",\s*entry\.appearance[^\]]*"--task-mode",\s*entry\.taskMode[^\]]*\]/s,
  "fixed Nexo skins must pass their vivid profile to the theme loader",
);
for (const [argument, field] of [
  ["--accent-rgb", "accentRGB"],
  ["--secondary-rgb", "secondaryRGB"],
  ["--panel-rgb", "panelRGB"],
  ["--glow-strength", "glowStrength"],
  ["--signature", "signature"],
  ["--focus-x", "focusX"],
  ["--focus-y", "focusY"],
  ["--layout-variant", "layoutVariant"],
  ["--surface-style", "surfaceStyle"],
  ["--corner-style", "cornerStyle"],
  ["--motion-preset", "motionPreset"],
  ["--sidebar-style", "sidebarStyle"],
  ["--composer-style", "composerStyle"],
  ["--texture-style", "textureStyle"],
]) {
  assert.match(
    appDelegate,
    new RegExp(`"${argument}",\\s*(?:String\\()?entry\\.visual\\.${field}`),
    `${argument} must reach the writer`,
  );
}
for (const argument of [
  "--layout-variant", "--surface-style", "--corner-style", "--motion-preset",
  "--sidebar-style", "--composer-style", "--texture-style",
]) {
  assert.match(loader, new RegExp(argument), `${argument} must be accepted by the macOS loader`);
}
assert.match(
  loader,
  /case "\$TASK_MODE" in auto\|ambient\|banner\|full\|off\)/,
  "the macOS loader must accept the full task-art mode used by fixed skins",
);
assert.match(
  loader,
  /-Z 3840 "\$IMAGE"/,
  "the macOS loader must preserve a 4K-wide skin master instead of downsampling it to 2400px",
);
assert.match(
  writer,
  /\["auto",\s*"ambient",\s*"banner",\s*"full",\s*"off"\]/,
  "the theme writer must preserve the full task-art mode",
);
assert.match(writer, /const visual\s*=\s*hasVisual\s*\?\s*\{[\s\S]*accentRGB[\s\S]*secondaryRGB[\s\S]*panelRGB[\s\S]*glowStrength[\s\S]*signature[\s\S]*layoutVariant[\s\S]*surfaceStyle[\s\S]*cornerStyle[\s\S]*motionPreset[\s\S]*sidebarStyle[\s\S]*composerStyle[\s\S]*textureStyle[\s\S]*\}/, "the writer must serialize the complete deep visual profile");

console.log("Nexo vivid profile tests passed");
