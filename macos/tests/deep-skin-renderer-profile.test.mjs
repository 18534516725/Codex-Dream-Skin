import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const renderer = await fs.readFile(path.join(root, "runtime/renderer-inject.js"), "utf8");

for (const [attribute, field] of [
  ["data-dream-layout", "layoutVariant"],
  ["data-dream-surface", "surfaceStyle"],
  ["data-dream-corners", "cornerStyle"],
  ["data-dream-motion", "motionPreset"],
  ["data-dream-sidebar-style", "sidebarStyle"],
  ["data-dream-composer-style", "composerStyle"],
  ["data-dream-texture", "textureStyle"],
]) {
  assert.match(
    renderer,
    new RegExp(`setAttribute\\(root, "${attribute}",[^;]*VISUAL\\.${field}`),
    `${attribute} must be derived from the validated ${field} profile`,
  );
}

assert.match(renderer, /const visualChoice\s*=\s*\(/, "renderer must validate profile choices before writing DOM attributes");
assert.match(renderer, /layoutVariant:[\s\S]*poster-right[\s\S]*pixel-console/, "renderer must whitelist layout variants");
assert.match(renderer, /motionPreset:[\s\S]*none[\s\S]*sonar/, "renderer must whitelist motion presets");
assert.match(renderer, /const compactThemeName\s*=\s*\(/, "renderer must derive compact home titles");
assert.match(renderer, /Array\.from\(compact\)\.slice\(0, 12\)/, "compact titles must be bounded to 12 visible characters");
assert.match(renderer, /setAttribute\(root, "data-dream-theme-id", themeId\)/, "renderer must expose the validated fixed theme ID");
assert.match(renderer, /setStyleProperty\(root, "--dream-skin-name", cssString\(compactThemeName\(/, "home title must use the compact display name");

console.log("Deep skin renderer profile tests passed");
