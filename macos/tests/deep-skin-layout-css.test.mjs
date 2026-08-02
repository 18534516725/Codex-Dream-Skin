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

console.log("Deep skin layout CSS tests passed");
