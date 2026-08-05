import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../..", import.meta.url));
const macAppDelegate = await readFile(
  `${root}/macos/menubar-app/Sources/CodexDreamSkinMenuBar/AppDelegate.swift`,
  "utf8"
);
const windowsApply = await readFile(`${root}/windows/scripts/apply-community-theme.ps1`, "utf8");
const windowsTray = await readFile(`${root}/windows/scripts/tray-dream-skin.ps1`, "utf8");

for (const [label, source] of [
  ["macOS one-click apply", macAppDelegate],
  ["Windows one-click apply", windowsApply],
  ["Windows tray", windowsTray],
]) {
  assert.equal(source.includes("verifyEntitlement"), false, `${label} must not verify an account entitlement`);
  assert.equal(source.includes("Ensure-DreamSkinNexoPairing"), false, `${label} must not pair an account`);
  assert.equal(source.includes("currentPairingStatus"), false, `${label} must not query pairing status`);
}

console.log("PASS: one-click skin application is local and never requires account validation.");
