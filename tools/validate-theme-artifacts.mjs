import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

import { readImageMetadata } from "../runtime/image-metadata.mjs";

const args = process.argv.slice(2);
const catalogIndex = args.indexOf("--catalog");
if (catalogIndex < 0 || !args[catalogIndex + 1]) throw new Error("Usage: validate-theme-artifacts.mjs --catalog <catalog.json>");
const catalogPath = path.resolve(args[catalogIndex + 1]);
const root = path.resolve(path.dirname(catalogPath), "..");
const catalog = JSON.parse(await fs.readFile(catalogPath, "utf8"));

for (const item of catalog.items) {
  const directory = path.join(path.dirname(catalogPath), "catalog", item.id);
  for (const [name, width, height, hashKey] of [
    ["background.webp", 3840, 2400, "poster"],
    ["preview.webp", 1200, 750, "preview"],
  ]) {
    const bytes = await fs.readFile(path.join(directory, name));
    assert.equal(bytes.subarray(0, 4).toString("ascii"), "RIFF");
    assert.equal(bytes.subarray(8, 12).toString("ascii"), "WEBP");
    const metadata = readImageMetadata(bytes, ".webp");
    assert.deepEqual([metadata?.width, metadata?.height], [width, height]);
    assert.equal(createHash("sha256").update(bytes).digest("hex"), item.hashes[hashKey]);
  }
}
process.stdout.write(`${JSON.stringify({ validated: catalog.items.length })}\n`);
