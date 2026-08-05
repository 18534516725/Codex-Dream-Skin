import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const source = await fs.readFile(path.join(root, "scripts/theme-windows.ps1"), "utf8");

assert.match(
  source,
  /function Test-DreamSkinSignedNexoCatalogKeyAvailability/,
  "the signed catalog key guard must be explicit and independently testable",
);
assert.doesNotMatch(
  source,
  /DreamSkinSignedNexoPublicKeys(?:\.Keys)?\)\.Count/,
  "the protocol handler must not use the PowerShell adapter-dependent Count property",
);
assert.match(
  source,
  /if \(Test-DreamSkinSignedNexoCatalogKeyAvailability\)/,
  "Nexo apply resolution must use the safe signing-key guard",
);

console.log("Windows signed Nexo key availability regression test passed");
