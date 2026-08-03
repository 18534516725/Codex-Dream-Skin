import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const [contract, catalogSource, appDelegate, loader, writer, appBuilder] = await Promise.all([
  fs.readFile(path.join(root, "menubar-app/Sources/DreamSkinCore/NexoSkinLink.swift"), "utf8"),
  fs.readFile(path.join(root, "menubar-app/Sources/DreamSkinCore/Resources/nexo-skin-catalog.json"), "utf8"),
  fs.readFile(path.join(root, "menubar-app/Sources/CodexDreamSkinMenuBar/AppDelegate.swift"), "utf8"),
  fs.readFile(path.join(root, "scripts/load-image-theme-macos.sh"), "utf8"),
  fs.readFile(path.join(root, "scripts/write-theme.mjs"), "utf8"),
  fs.readFile(path.join(root, "scripts/build-menubar-app.sh"), "utf8"),
]);

assert.doesNotMatch(contract, /Bundle\.module\.url/, "installed app catalog lookup must never trap when a SwiftPM resource bundle is absent");
assert.match(contract, /Bundle\.main\.url\(forResource: "nexo-skin-catalog"/, "installed app must load its catalog from the signed app resources");
assert.match(contract, /for _ in 0\.\.<5/, "SwiftPM test fallback must search only a bounded set of parent directories");
assert.match(appBuilder, /nexo-skin-catalog\.json/, "native app builder must package the fixed catalog beside the app resources");

for (const field of [
  "accentRGB", "secondaryRGB", "panelRGB", "glowStrength", "signature", "focusX", "focusY",
  "layoutVariant", "surfaceStyle", "cornerStyle", "motionPreset", "sidebarStyle", "composerStyle", "textureStyle",
]) {
  assert.match(contract, new RegExp(`public let ${field}:`), `macOS fixed skin profiles must expose ${field}`);
}
const catalog = JSON.parse(catalogSource);
assert.equal(catalog.schemaVersion, 2, "macOS must consume the Theme V2 catalog");
assert.equal(catalog.items.length, 18, "macOS must package all 18 fixed skins");
for (const id of [
  "post-raccoon", "night-shift-penguin", "workshop-otter",
  "moon-platform-cat", "floppy-wizard", "deep-sea-repair",
]) {
  assert.ok(catalog.items.some((item) => item.id === id), `macOS must expose ${id}`);
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
