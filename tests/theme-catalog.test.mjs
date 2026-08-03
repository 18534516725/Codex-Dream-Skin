import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import { validateThemeV2 } from "../themes/theme-v2.mjs";

const root = path.resolve(import.meta.dirname, "..");
const catalog = JSON.parse(await fs.readFile(path.join(root, "themes", "catalog.json"), "utf8"));

test("generated theme catalog is strict, unique and cross-platform", () => {
  assert.equal(catalog.schemaVersion, 2);
  assert.equal(catalog.items.length, 18);
  assert.equal(new Set(catalog.items.map((item) => item.id)).size, 18);
  for (const item of catalog.items) {
    assert.equal(validateThemeV2(item.theme).id, item.id);
    assert.deepEqual(item.platforms, ["macos", "windows"]);
    assert.match(item.hashes.theme, /^[a-f0-9]{64}$/);
    assert.match(item.hashes.poster, /^[a-f0-9]{64}$/);
  }
});
