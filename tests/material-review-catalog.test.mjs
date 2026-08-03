import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import test from "node:test";

const root = path.resolve(import.meta.dirname, "..");
const catalog = JSON.parse(await fs.readFile(path.join(root, "themes", "material-review-catalog.json"), "utf8"));

test("review catalog records all unique candidate themes", () => {
  assert.equal(catalog.sourceCount, 71);
  assert.equal(catalog.uniqueThemeCount, 69);
  assert.equal(catalog.duplicateCount, 2);
  assert.equal(catalog.items.length, 69);
  assert.equal(new Set(catalog.items.map((item) => item.id)).size, 69);
  assert.equal(catalog.publicThemeCount, 0);
});

test("review catalog contains reproducible 4K artifacts without local paths", () => {
  assert.ok(catalog.items.every((item) => item.poster.width === 3840 && item.poster.height === 2400));
  assert.ok(catalog.items.every((item) => item.preview.width === 1200 && item.preview.height === 750));
  assert.ok(catalog.items.every((item) => /^[a-f0-9]{64}$/.test(item.poster.sha256)));
  assert.ok(catalog.items.every((item) => /^[a-f0-9]{64}$/.test(item.preview.sha256)));
  assert.ok(catalog.items.every((item) => ["admin_review_only", "blocked_pending_rights_review"].includes(item.publication)));
  assert.doesNotMatch(JSON.stringify(catalog), /\/Users\/|[A-Z]:\\\\/);
});
