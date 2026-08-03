import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

import { readImageMetadata } from "../runtime/image-metadata.mjs";

const args = process.argv.slice(2);
const catalogIndex = args.indexOf("--catalog");
const materialsIndex = args.indexOf("--materials");
const privateIndex = args.indexOf("--allow-private");
if (catalogIndex < 0 && materialsIndex < 0) {
  throw new Error("Usage: validate-theme-artifacts.mjs --catalog <catalog.json> | --materials <materials.json> --allow-private <directory>");
}

async function verifyWebp(filePath, width, height) {
  const bytes = await fs.readFile(filePath);
  assert.equal(bytes.subarray(0, 4).toString("ascii"), "RIFF");
  assert.equal(bytes.subarray(8, 12).toString("ascii"), "WEBP");
  const metadata = readImageMetadata(bytes, ".webp");
  assert.deepEqual([metadata?.width, metadata?.height], [width, height]);
  return bytes;
}

if (catalogIndex >= 0) {
  const catalogPath = path.resolve(args[catalogIndex + 1]);
  const catalog = JSON.parse(await fs.readFile(catalogPath, "utf8"));
  for (const item of catalog.items) {
    const directory = path.join(path.dirname(catalogPath), "catalog", item.id);
    for (const [name, width, height, hashKey] of [
      ["background.webp", 3840, 2400, "poster"],
      ["preview.webp", 1200, 750, "preview"],
    ]) {
      const bytes = await verifyWebp(path.join(directory, name), width, height);
      assert.equal(createHash("sha256").update(bytes).digest("hex"), item.hashes[hashKey]);
    }
  }
  process.stdout.write(`${JSON.stringify({ validated: catalog.items.length })}\n`);
} else {
  if (privateIndex < 0 || !args[privateIndex + 1]) throw new Error("--allow-private is required for material candidates");
  const materialsPath = path.resolve(args[materialsIndex + 1]);
  const privateRoot = path.resolve(args[privateIndex + 1]);
  const materials = JSON.parse(await fs.readFile(materialsPath, "utf8"));
  let validated = 0;
  for (const item of materials.items) {
    if (item.status === "duplicate" || item.status === "failed") continue;
    const directory = path.join(privateRoot, item.outputThemeId);
    const theme = JSON.parse(await fs.readFile(path.join(directory, "theme.json"), "utf8"));
    assert.equal(theme.id, item.outputThemeId);
    await verifyWebp(path.join(directory, "background.webp"), 3840, 2400);
    await verifyWebp(path.join(directory, "preview.webp"), 1200, 750);
    if (item.videoDisposition === "true-dynamic") {
      const video = await fs.readFile(path.join(directory, "background.mp4"));
      assert.ok(video.length > 0 && video.length <= 80 * 1024 * 1024);
      assert.equal(video.subarray(4, 8).toString("ascii"), "ftyp");
    }
    validated += 1;
  }
  process.stdout.write(`${JSON.stringify({ validated })}\n`);
}
