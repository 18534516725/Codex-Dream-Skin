import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import test from "node:test";

const root = path.resolve(import.meta.dirname, "..");
const manifest = JSON.parse(await fs.readFile(path.join(root, "themes", "source-materials.json"), "utf8"));

test("source material inventory covers every current Downloads media file", () => {
  assert.equal(manifest.schemaVersion, 1);
  assert.equal(manifest.sourceCount, 71);
  assert.equal(manifest.items.length, 71);
  assert.equal(new Set(manifest.items.map((item) => item.sourcePath)).size, 71);
  assert.ok(manifest.items.every((item) => /^[a-f0-9]{64}$/.test(item.sha256)));
  assert.ok(manifest.items.every((item) => ["static", "video"].includes(item.kind)));
  assert.ok(manifest.items.every((item) => ["jpeg", "png", "webp", "mp4"].includes(item.actualFormat)));
  assert.ok(manifest.items.every((item) => Number.isInteger(item.bytes) && item.bytes > 0));
  assert.ok(manifest.items.every((item) => item.width === null || Number.isInteger(item.width)));
  assert.ok(manifest.items.every((item) => item.height === null || Number.isInteger(item.height)));
  assert.ok(manifest.items.some((item) => item.status === "duplicate"));
  assert.ok(manifest.items.filter((item) => item.status === "duplicate").every((item) => item.canonicalId));
});

test("inventory IDs and ordering are deterministic", () => {
  assert.deepEqual(manifest.items.map((item) => item.sourcePath), [...manifest.items.map((item) => item.sourcePath)].sort((a, b) => a.localeCompare(b, "zh-CN")));
  assert.equal(new Set(manifest.items.map((item) => item.id)).size, 71);
  assert.ok(manifest.items.every((item) => /^material-[a-f0-9]{12}-[a-f0-9]{8}$/.test(item.id)));
});
