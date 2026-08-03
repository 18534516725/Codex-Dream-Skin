import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const attributes = await fs.readFile(path.join(root, ".gitattributes"), "utf8");

for (const rule of [
  "runtime/** text eol=lf",
  "windows/assets/** text eol=lf",
  "windows/scripts/image-metadata.mjs text eol=lf",
]) {
  assert.ok(attributes.includes(rule), `missing byte-stable Windows checkout rule: ${rule}`);
}

console.log("Windows runtime line-ending contract passed");
