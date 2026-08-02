import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, "..");
const [appDelegate, loader, writer] = await Promise.all([
  fs.readFile(path.join(root, "menubar-app/Sources/CodexDreamSkinMenuBar/AppDelegate.swift"), "utf8"),
  fs.readFile(path.join(root, "scripts/load-image-theme-macos.sh"), "utf8"),
  fs.readFile(path.join(root, "scripts/write-theme.mjs"), "utf8"),
]);

assert.match(
  appDelegate,
  /arguments:\s*\[[^\]]*"--appearance",\s*entry\.appearance[^\]]*"--task-mode",\s*entry\.taskMode[^\]]*\]/s,
  "fixed Nexo skins must pass their vivid profile to the theme loader",
);
assert.match(
  loader,
  /case "\$TASK_MODE" in auto\|ambient\|banner\|full\|off\)/,
  "the macOS loader must accept the full task-art mode used by fixed skins",
);
assert.match(
  writer,
  /\["auto",\s*"ambient",\s*"banner",\s*"full",\s*"off"\]/,
  "the theme writer must preserve the full task-art mode",
);

console.log("Nexo vivid profile tests passed");
