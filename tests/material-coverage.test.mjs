import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import test from "node:test";

const root = path.resolve(import.meta.dirname, "..");
const manifest = JSON.parse(await fs.readFile(path.join(root, "themes", "source-materials.json"), "utf8"));

test("every inventoried source has a concrete theme outcome", () => {
  const allowed = new Set(["ready", "duplicate", "copyright_review", "reference_only", "failed"]);
  assert.equal(manifest.items.length, 71);
  assert.ok(manifest.items.every((item) => allowed.has(item.status)));
  assert.ok(manifest.items.every((item) => item.status === "duplicate" || item.outputThemeId || item.failureReason));
  assert.ok(manifest.items.filter((item) => item.kind === "video" && item.status !== "duplicate").every((item) => ["true-dynamic", "ambient-reconstruction"].includes(item.videoDisposition)));
});
