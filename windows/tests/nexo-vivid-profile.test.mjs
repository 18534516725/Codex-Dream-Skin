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
assert.match(
  applyScript,
  /Set-DreamSkinActiveTheme[^\r\n]*-Theme\s+\$themeProfile/,
  "Windows must pass the fixed skin profile into theme generation",
);

console.log("Windows Nexo vivid profile tests passed");
