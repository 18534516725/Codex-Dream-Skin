import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const masters = path.join(root, "artwork/masters");
const palettes = path.join(root, "artwork/palettes");

for (const [file, minimumBytes] of [["13-post-raccoon.png", 500_000], ["16-moon-platform-cat.png", 250_000]]) {
  const imagePath = path.join(masters, file);
  const stat = await fs.stat(imagePath);
  assert.ok(stat.size > minimumBytes, `${file} must be a detailed lossless master`);
  const dimensions = execFileSync("magick", ["identify", "-format", "%w %h", imagePath], { encoding: "utf8" }).trim();
  assert.equal(dimensions, "3840 2400", `${file} must be a 3840×2400 master`);
}

const raccoon = JSON.parse(await fs.readFile(path.join(palettes, "13-post-raccoon.json"), "utf8"));
assert.equal(raccoon.id, "post-raccoon");
assert.equal(raccoon.medium, "cel-animation-paper");
assert.ok(raccoon.colors.length >= 5 && raccoon.colors.length <= 16);

const pixel = JSON.parse(await fs.readFile(path.join(palettes, "16-moon-platform-cat.json"), "utf8"));
assert.equal(pixel.id, "moon-platform-cat");
assert.equal(pixel.medium, "16-bit-pixel");
assert.equal(pixel.pixelGrid, 8);
assert.equal(pixel.antialias, false);
assert.ok(pixel.colors.length >= 8 && pixel.colors.length <= 32);

console.log("Artwork quality tests passed");
