import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import { readImageMetadata } from "../runtime/image-metadata.mjs";

const root = path.resolve(import.meta.dirname, "..");
const catalog = JSON.parse(await fs.readFile(path.join(root, "themes", "catalog.json"), "utf8"));

test("every existing theme has true WebP 4K art and a rich 1200x750 preview", async () => {
  for (const item of catalog.items) {
    const directory = path.join(root, "themes", "catalog", item.id);
    for (const [name, expected, hashKey] of [
      ["background.webp", [3840, 2400], "poster"],
      ["preview.webp", [1200, 750], "preview"],
    ]) {
      const bytes = await fs.readFile(path.join(directory, name));
      assert.equal(bytes.subarray(0, 4).toString("ascii"), "RIFF", `${item.id}/${name} is not WebP`);
      assert.equal(bytes.subarray(8, 12).toString("ascii"), "WEBP", `${item.id}/${name} is not WebP`);
      const metadata = readImageMetadata(bytes, ".webp");
      assert.deepEqual([metadata?.width, metadata?.height], expected, `${item.id}/${name} has wrong dimensions`);
      assert.equal(createHash("sha256").update(bytes).digest("hex"), item.hashes[hashKey]);
    }
  }
});
