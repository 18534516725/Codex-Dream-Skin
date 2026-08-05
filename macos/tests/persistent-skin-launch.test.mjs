import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const app = await fs.readFile(
  path.join(root, "macos/menubar-app/Sources/CodexDreamSkinMenuBar/AppDelegate.swift"),
  "utf8",
);

assert.match(app, /resumeActiveSkinAfterLogin\(snapshot:/,
  "an enabled login helper must restore the saved skin through the audited launch path");
assert.match(app, /SMAppService\.mainApp\.status == \.enabled/,
  "automatic restore must be opt-in through the existing login-item control");
assert.match(app, /snapshot\.session == "stale"[\s\S]*!snapshot\.codexRunning/,
  "automatic restore must only start a closed Codex with a previously verified skin state");
assert.match(app, /runInstalledScript\(named: "apply-from-menubar-macos\.sh", operation: "恢复已选皮肤"\)/,
  "automatic restore must reuse the existing verified launcher, not mutate Codex itself");
assert.doesNotMatch(app, /terminateApplication|forceTerminate|killall.*Codex|pkill.*Codex/,
  "persistent skin startup must never force-close Codex");

console.log("Persistent macOS skin launch regression test passed");
