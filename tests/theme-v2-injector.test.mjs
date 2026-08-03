import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import { loadPayload as loadMacPayload, loadTheme as loadMacTheme } from "../macos/scripts/injector.mjs";
import { loadPayload as loadWindowsPayload, loadTheme as loadWindowsTheme } from "../windows/scripts/injector.mjs";

const root = path.resolve(import.meta.dirname, "..");

async function createDynamicTheme() {
  const themeDir = await fs.mkdtemp("/tmp/dream-skin-v2-injector-");
  const poster = await fs.readFile(path.join(root, "docs", "images", "site-studio-zh.webp"));
  const video = Buffer.concat([
    Buffer.from([0, 0, 0, 24]), Buffer.from("ftypisom"),
    Buffer.from([0, 0, 0, 0]), Buffer.from("isomavc1"),
  ]);
  const theme = {
    schemaVersion: 2,
    id: "dynamic-sakura",
    name: "动态樱花",
    appearance: "dark",
    family: "cartoon-stationery",
    media: { poster: "background.webp", video: "background.mp4" },
    typography: { body: "native-sans", title: "rounded", label: "rounded", code: "native-mono" },
    visual: {
      layout: "poster-right", surface: "paper", corners: "stamp", motion: "petals",
      sidebar: "garden", composer: "letter", texture: "wash",
    },
    colors: {
      background: "#19141f", panel: "#211a29", panelAlt: "#2a2134", accent: "#e897be",
      secondary: "#a689e8", text: "#fff8fc", muted: "#cabdca", line: "#735b7d",
    },
    art: { focusX: 0.72, focusY: 0.45, safeArea: "left", taskMode: "ambient" },
    risk: { status: "approved", note: "original" },
  };
  await Promise.all([
    fs.writeFile(path.join(themeDir, "theme.json"), `${JSON.stringify(theme)}\n`),
    fs.writeFile(path.join(themeDir, "background.webp"), poster),
    fs.writeFile(path.join(themeDir, "background.mp4"), video),
  ]);
  return { themeDir, poster, video };
}

for (const [platform, loadTheme, loadPayload] of [
  ["macOS", loadMacTheme, loadMacPayload],
  ["Windows", loadWindowsTheme, loadWindowsPayload],
]) {
  test(`${platform} loads Theme V2 poster, video, profile and complete payload`, async (t) => {
    const fixture = await createDynamicTheme();
    t.after(() => fs.rm(fixture.themeDir, { recursive: true, force: true }));
    const loaded = await loadTheme(fixture.themeDir);
    assert.equal(loaded.theme.schemaVersion, 2);
    assert.equal(loaded.theme.family, "cartoon-stationery");
    assert.deepEqual(loaded.imageBytes ?? loaded.art, fixture.poster);
    assert.deepEqual(loaded.videoBytes, fixture.video);
    assert.match(loaded.theme.renderProfile["--ds-font-title"], /Rounded|Nunito|Quicksand/i);
    const payload = await loadPayload(fixture.themeDir, platform === "Windows" ? loaded : null);
    assert.doesNotMatch(payload.payload, /__DREAM_SKIN_[A-Z0-9_]+_JSON__/);
    assert.match(payload.payload, /data:video\/mp4;base64,/);
    await fs.appendFile(path.join(fixture.themeDir, "background.mp4"), Buffer.from("avc1"));
    const changed = await loadPayload(fixture.themeDir);
    assert.notEqual(changed.revision, payload.revision, "video changes must invalidate the payload revision");
  });
}
