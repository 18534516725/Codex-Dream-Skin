import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const [css, renderer, macCss, winCss, macRenderer, winRenderer] = await Promise.all([
  fs.readFile(path.join(root, "runtime/dream-skin.css"), "utf8"),
  fs.readFile(path.join(root, "runtime/renderer-inject.js"), "utf8"),
  fs.readFile(path.join(root, "macos/assets/dream-skin.css"), "utf8"),
  fs.readFile(path.join(root, "windows/assets/dream-skin.css"), "utf8"),
  fs.readFile(path.join(root, "macos/assets/renderer-inject.js"), "utf8"),
  fs.readFile(path.join(root, "windows/assets/renderer-inject.js"), "utf8"),
]);

assert.equal(macCss, winCss, "macOS and Windows CSS must compile identically from the canonical runtime asset");
assert.equal(macRenderer, winRenderer, "macOS and Windows renderers must compile identically from the canonical runtime asset");

assert.match(renderer, /const VISUAL\s*=\s*THEME\.visual/, "renderer must consume the fixed-skin visual profile");
for (const variable of ["--ds-accent-rgb", "--ds-secondary-rgb", "--ds-panel-rgb", "--ds-glow-strength", "--dream-skin-signature"]) {
  assert.ok(renderer.includes(variable), `renderer must set ${variable}`);
}

assert.match(
  css,
  /__DREAM_SELECTOR_SHELL_MAIN__:has\(__DREAM_SELECTOR_HOME_ROUTE_CSS__\)::before\s*\{[^}]*background-image:[^}]*var\(--dream-skin-art\)/s,
  "the native home shell must paint the continuous wallpaper",
);
assert.match(css, /__DREAM_SELECTOR_LEFT_PANEL__\s*\{[^}]*backdrop-filter:\s*blur/s, "sidebar must have a refined translucent treatment");
assert.match(css, /\[aria-current="page"\][^{}]*\{[^}]*box-shadow:[^}]*--ds-accent-rgb/s, "selected projects must glow with the skin accent");
assert.match(css, /__DREAM_SELECTOR_COMPOSER_CHROME__::after\s*\{[^}]*content:\s*var\(--dream-skin-signature/s, "composer must carry the non-interactive theme signature");
assert.match(css, /__DREAM_SELECTOR_COMPOSER_CHROME__:focus-within\s*\{[^}]*--ds-accent-rgb/s, "composer focus must use the skin accent");
assert.match(css, /@media\s*\(prefers-reduced-motion:\s*reduce\)/, "theme motion must respect reduced-motion preferences");

console.log("signature skin CSS tests passed");
