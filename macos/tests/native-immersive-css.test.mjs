import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const css = await fs.readFile(path.resolve(here, "../../runtime/dream-skin.css"), "utf8");

assert.match(
  css,
  /data-dream-shell="dark"[^{}]*\{[^}]*--color-text-foreground:\s*var\(--ds-text\)\s*!important;/s,
  "dark Dream Skin sessions must remap the native foreground token",
);
assert.match(
  css,
  /data-dream-shell="dark"[^{}]*\{[^}]*--color-background-surface:\s*rgb\(var\(--ds-panel-rgb\)\s*\/\s*\.88\)\s*!important;/s,
  "dark Dream Skin sessions must remap native light surfaces",
);
assert.match(
  css,
  /__DREAM_SELECTOR_HEADER_TINT__::before\s*\{[^}]*content:\s*none\s*!important;/s,
  "task headers must not render theme advertising",
);
assert.match(
  css,
  /__DREAM_SELECTOR_HEADER_TINT__::after\s*\{[^}]*content:\s*none\s*!important;/s,
  "task headers must not render a theme status badge",
);

console.log("native immersive CSS tests passed");
