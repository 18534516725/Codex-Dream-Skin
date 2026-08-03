import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "../..");
const masters = path.join(root, "artwork/masters");
const palettes = path.join(root, "artwork/palettes");

const expected = [
  ["01-stellar-voyager", "stellar-voyager"],
  ["02-sakura-signal", "sakura-signal"],
  ["03-neon-courier", "neon-courier"],
  ["04-mist-beacon", "mist-beacon"],
  ["05-rain-harbor", "rain-harbor"],
  ["06-crimson-forge", "crimson-forge"],
  ["07-cloud-antler", "cloud-antler"],
  ["08-midnight-terminal", "midnight-terminal"],
  ["09-retro-orbit", "retro-orbit"],
  ["10-strategy-atrium", "strategy-atrium"],
  ["11-aurora-leviathan", "aurora-leviathan"],
  ["12-ink-ridge-guardian", "ink-ridge-guardian"],
  ["13-post-raccoon", "post-raccoon"],
  ["14-night-shift-penguin", "night-shift-penguin"],
  ["15-workshop-otter", "workshop-otter"],
  ["16-moon-platform-cat", "moon-platform-cat"],
  ["17-floppy-wizard", "floppy-wizard"],
  ["18-deep-sea-repair", "deep-sea-repair"],
];

for (const [basename, id] of expected) {
  const file = `${basename}.png`;
  const minimumBytes = ["retro-orbit", "moon-platform-cat", "floppy-wizard", "deep-sea-repair"].includes(id)
    ? 180_000 : 500_000;
  const imagePath = path.join(masters, file);
  const stat = await fs.stat(imagePath);
  assert.ok(stat.size > minimumBytes, `${file} must be a detailed lossless master`);
  const dimensions = execFileSync("magick", ["identify", "-format", "%w %h", imagePath], { encoding: "utf8" }).trim();
  assert.equal(dimensions, "3840 2400", `${file} must be a 3840×2400 master`);
  const palette = JSON.parse(await fs.readFile(path.join(palettes, `${basename}.json`), "utf8"));
  assert.equal(palette.id, id, `${basename} palette id must match the catalog`);
  assert.ok(Array.isArray(palette.colors) && palette.colors.length >= 4 && palette.colors.length <= 32);
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

for (const basename of ["09-retro-orbit", "16-moon-platform-cat", "17-floppy-wizard", "18-deep-sea-repair"]) {
  const palette = JSON.parse(await fs.readFile(path.join(palettes, `${basename}.json`), "utf8"));
  assert.equal(palette.pixelGrid, 8, `${basename} must preserve an 8px logical grid`);
  assert.equal(palette.antialias, false, `${basename} must remain hard-edged pixel art`);
}

console.log("Artwork quality tests passed");
