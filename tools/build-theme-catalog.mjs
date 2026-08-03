import { createHash } from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

import { validateThemeV2 } from "../themes/theme-v2.mjs";

const root = path.resolve(import.meta.dirname, "..");
const ids = [
  "stellar-voyager", "sakura-signal", "neon-courier", "mist-beacon", "rain-harbor", "crimson-forge",
  "cloud-antler", "midnight-terminal", "retro-orbit", "strategy-atrium", "aurora-leviathan", "ink-ridge-guardian",
  "post-raccoon", "night-shift-penguin", "workshop-otter", "moon-platform-cat", "floppy-wizard", "deep-sea-repair",
];

const items = [];
for (const [index, id] of ids.entries()) {
  const directory = path.join(root, "themes", "catalog", id);
  const themeBytes = await fs.readFile(path.join(directory, "theme.json"));
  const theme = validateThemeV2(JSON.parse(themeBytes.toString("utf8")));
  if (theme.id !== id) throw new Error(`${id} has a mismatched theme id`);
  const poster = await fs.readFile(path.join(directory, theme.media.poster));
  const video = theme.media.video ? await fs.readFile(path.join(directory, theme.media.video)) : null;
  items.push({
    id,
    name: theme.name,
    version: 2,
    family: theme.family,
    appearance: theme.appearance,
    mediaKind: video ? "video" : "static",
    riskStatus: theme.risk.status,
    assetFile: `${String(index + 1).padStart(2, "0")}-${id}.webp`,
    platforms: ["macos", "windows"],
    hashes: {
      theme: createHash("sha256").update(themeBytes).digest("hex"),
      poster: createHash("sha256").update(poster).digest("hex"),
      video: video ? createHash("sha256").update(video).digest("hex") : null,
    },
    theme,
  });
}

const catalog = {
  schemaVersion: 2,
  assetOrigin: "https://nexotoken.net",
  items,
};
const output = `${JSON.stringify(catalog, null, 2)}\n`;
const targets = [
  path.join(root, "themes", "catalog.json"),
  path.join(root, "macos", "menubar-app", "Sources", "DreamSkinCore", "Resources", "nexo-skin-catalog.json"),
  path.join(root, "windows", "assets", "nexo-skin-catalog.json"),
];
for (const target of targets) {
  await fs.mkdir(path.dirname(target), { recursive: true });
  await fs.writeFile(target, output, "utf8");
}
process.stdout.write(`${JSON.stringify({ themes: items.length })}\n`);
