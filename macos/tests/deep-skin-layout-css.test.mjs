import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const css = await fs.readFile(path.join(root, "runtime/dream-skin.css"), "utf8");

for (const value of [
  "poster-right", "editorial", "stage", "console", "collage",
  "pixel-platform", "pixel-desktop", "pixel-console",
]) assert.match(css, new RegExp(`data-dream-layout="${value}"`), `missing ${value} home layout`);

for (const value of ["glass", "paper", "metal", "ink", "pixel"]) {
  assert.match(css, new RegExp(`data-dream-surface="${value}"`), `missing ${value} surface system`);
}
for (const value of ["round", "cut", "stamp", "pixel", "tape", "ticket"]) {
  assert.match(css, new RegExp(`data-dream-corners="${value}"`), `missing ${value} corner system`);
}
for (const value of ["garden", "postal", "terminal", "station", "submarine"]) {
  assert.match(css, new RegExp(`data-dream-sidebar-style="${value}"`), `missing ${value} sidebar treatment`);
}
for (const value of ["letter", "terminal", "workbench", "pixel-console", "sonar"]) {
  assert.match(css, new RegExp(`data-dream-composer-style="${value}"`), `missing ${value} composer treatment`);
}
for (const value of ["petals", "rain", "sparks", "mail", "spotlight", "doodle", "pixel-rain", "cursor", "sonar"]) {
  assert.match(css, new RegExp(`data-dream-motion="${value}"`), `missing ${value} motion preset`);
}

assert.match(css, /--ds-reading-veil:/, "task pages need a bounded reading veil token");
assert.match(css, /not\(:has\(__DREAM_SELECTOR_HOME_ROUTE_CSS__\)\)[\s\S]*--ds-reading-veil/, "non-home pages must use the reading veil");
assert.match(css, /pointer-events:\s*none/, "decorative layers must never intercept native controls");
assert.match(css, /prefers-reduced-motion:\s*reduce[\s\S]*animation:\s*none\s*!important/, "reduced motion must disable environmental animation");
assert.match(css, /__DREAM_SELECTOR_GAME_SOURCE__\s*\{[\s\S]*font-size:\s*0\s*!important/, "home must hide inherited long headline text");
assert.match(css, /__DREAM_SELECTOR_GAME_SOURCE__::after\s*\{[\s\S]*display:\s*none\s*!important/, "home must hide the secondary tagline");
assert.match(
  css,
  /__DREAM_SELECTOR_GAME_SOURCE__ button\s*\{[^}]*display:\s*none\s*!important/,
  "home must hide the selected-project pill after a skin is applied",
);
assert.match(css, /data-dream-theme-id="material-df6388daee46-e3486a16"[\s\S]*body::after/, "only the selected skin may disable the particle layer");
assert.match(css, /data-dream-theme-id="material-df6388daee46-e3486a16"[\s\S]*__DREAM_SELECTOR_LEFT_PANEL__::after/, "only the selected skin may disable the sidebar texture");
assert.match(css, /data-dream-theme-id="nexo-material-df6388daee46-e3486a16"[\s\S]*body::after/, "the selected Windows fixed-skin ID must disable the particle layer too");
assert.doesNotMatch(
  css,
  /@media \(max-width:\s*900px\)[\s\S]*?__DREAM_SELECTOR_GAME_SOURCE__\s*\{\s*font-size:\s*18px\s*!important;/,
  "narrow windows must never restore the native marketplace headline",
);
assert.match(
  css,
  /@media \(max-width:\s*900px\)[\s\S]*?__DREAM_SELECTOR_GAME_SOURCE__\s*\{\s*font-size:\s*0\s*!important;/,
  "narrow windows must keep the native marketplace headline hidden",
);

console.log("Deep skin layout CSS tests passed");
