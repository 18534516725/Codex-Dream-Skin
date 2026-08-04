import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const source = await fs.readFile(
  path.join(root, "macos/menubar-app/Sources/CodexDreamSkinMenuBar/AppDelegate.swift"),
  "utf8",
);
const method = source.match(/@objc private func openCodex\(\) \{([\s\S]*?)\n  \}/)?.[1] ?? "";

assert.match(method, /runInstalledScript\(\s*named:\s*"apply-from-menubar-macos\.sh"/,
  "Opening Codex from the helper must enter the skin launch path, not normal app launch.");
assert.doesNotMatch(method, /NSWorkspace\.shared\.openApplication/,
  "The helper's open action must not silently start an unskinned Codex process.");

console.log("Open Codex skin-launch regression test passed");
