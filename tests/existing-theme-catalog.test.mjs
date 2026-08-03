import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import { readImageMetadata } from "../runtime/image-metadata.mjs";
import { buildThemeProfile } from "../runtime/theme-profile.mjs";
import { validateThemeV2 } from "../themes/theme-v2.mjs";

const root = path.resolve(import.meta.dirname, "..");
const ids = [
  "stellar-voyager", "sakura-signal", "neon-courier", "mist-beacon", "rain-harbor", "crimson-forge",
  "cloud-antler", "midnight-terminal", "retro-orbit", "strategy-atrium", "aurora-leviathan", "ink-ridge-guardian",
  "post-raccoon", "night-shift-penguin", "workshop-otter", "moon-platform-cat", "floppy-wizard", "deep-sea-repair",
];

test("all 18 existing themes are complete Theme V2 packages", async () => {
  const signatures = new Set();
  for (const id of ids) {
    const directory = path.join(root, "themes", "catalog", id);
    const theme = validateThemeV2(JSON.parse(await fs.readFile(path.join(directory, "theme.json"), "utf8")));
    assert.equal(theme.id, id);
    assert.equal(theme.media.poster, "background.webp");
    assert.equal(theme.media.video, null);
    assert.equal(theme.risk.status, "approved");
    const profile = buildThemeProfile(theme);
    for (const key of ["--ds-font-body", "--ds-font-title", "--ds-font-label", "--ds-font-code", "--ds-sidebar-bg", "--ds-sidebar-text", "--ds-sidebar-hover", "--ds-sidebar-selected"]) {
      assert.ok(profile[key], `${id} missing ${key}`);
    }
    signatures.add(`${theme.family}:${theme.visual.sidebar}:${theme.visual.composer}:${theme.colors.accent}`);
    const poster = await fs.readFile(path.join(directory, "background.webp"));
    const metadata = readImageMetadata(poster, ".webp");
    assert.deepEqual([metadata?.width, metadata?.height], [3840, 2400], `${id} poster must be 4K workspace art`);
  }
  assert.equal(signatures.size, 18, "each existing theme needs a distinct logical profile");
});

test("generated native catalogs match the canonical catalog", async () => {
  const catalog = JSON.parse(await fs.readFile(path.join(root, "themes", "catalog.json"), "utf8"));
  const mac = JSON.parse(await fs.readFile(path.join(root, "macos", "menubar-app", "Sources", "DreamSkinCore", "Resources", "nexo-skin-catalog.json"), "utf8"));
  const windows = JSON.parse(await fs.readFile(path.join(root, "windows", "assets", "nexo-skin-catalog.json"), "utf8"));
  assert.deepEqual(catalog.items.map((item) => item.id), ids);
  assert.deepEqual(mac, catalog);
  assert.deepEqual(windows, catalog);
  const swift = await fs.readFile(path.join(root, "macos", "menubar-app", "Sources", "DreamSkinCore", "NexoSkinLink.swift"), "utf8");
  const powershell = await fs.readFile(path.join(root, "windows", "scripts", "theme-windows.ps1"), "utf8");
  assert.doesNotMatch(swift, /private static let (files|profiles)/);
  assert.doesNotMatch(powershell, /DreamSkinNexoCatalog\s*=\s*@\{/);
});
