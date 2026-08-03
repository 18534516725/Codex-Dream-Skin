import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import { buildThemeProfile, FONT_STACKS } from "../runtime/theme-profile.mjs";

const root = path.resolve(import.meta.dirname, "..");
const css = await fs.readFile(path.join(root, "runtime", "dream-skin.css"), "utf8");
const renderer = await fs.readFile(path.join(root, "runtime", "renderer-inject.js"), "utf8");

const theme = {
  schemaVersion: 2,
  family: "cartoon-stationery",
  typography: { body: "native-sans", title: "rounded", label: "rounded", code: "native-mono" },
  colors: {
    background: "#19141f", panel: "#211a29", panelAlt: "#2a2134", accent: "#e897be",
    secondary: "#a689e8", text: "#fff8fc", muted: "#cabdca", line: "#735b7d",
  },
};

test("Theme V2 maps readable cross-platform typography and sidebar colors", () => {
  const profile = buildThemeProfile(theme);
  assert.match(profile["--ds-font-body"], /PingFang SC/);
  assert.match(profile["--ds-font-body"], /Microsoft YaHei/);
  assert.match(profile["--ds-font-code"], /Consolas/);
  assert.equal(profile["--ds-font-title"], FONT_STACKS.rounded);
  assert.equal(profile["--ds-sidebar-text"], "#fff8fc");
  assert.equal(profile["--ds-sidebar-muted"], "#cabdca");
  assert.match(profile["--ds-sidebar-selected"], /^rgb\(/);
  assert.match(profile["--ds-sidebar-hover"], /^rgb\(/);
});

test("Every visual family produces a distinct, complete profile", () => {
  const families = [
    "cinematic-cyber", "nature-healing", "warm-editorial",
    "cartoon-stationery", "pixel-retro", "celestial-fantasy",
  ];
  const profiles = families.map((family) => buildThemeProfile({ ...theme, family }));
  assert.equal(new Set(profiles.map((profile) => profile["--ds-family-signature"])).size, 6);
  for (const profile of profiles) {
    for (const key of [
      "--ds-font-body", "--ds-font-title", "--ds-font-label", "--ds-font-code",
      "--ds-sidebar-bg", "--ds-sidebar-text", "--ds-sidebar-muted",
      "--ds-sidebar-hover", "--ds-sidebar-selected", "--ds-sidebar-border",
    ]) assert.ok(profile[key], `${key} must be defined`);
  }
});

test("Renderer applies family state and clears every new root token", () => {
  assert.match(renderer, /data-dream-family/);
  for (const variable of [
    "--ds-font-body", "--ds-font-title", "--ds-font-label", "--ds-font-code",
    "--ds-sidebar-bg", "--ds-sidebar-text", "--ds-sidebar-muted",
    "--ds-sidebar-hover", "--ds-sidebar-selected", "--ds-sidebar-border",
  ]) assert.ok(renderer.includes(`"${variable}"`), `${variable} must be registered by the renderer`);
});

test("Renderer records the mounted media layer before any later theme cleanup", () => {
  assert.match(
    renderer,
    /ensure\(\{ root: true, parts: true \}\);\s*if \(window\[STATE_KEY\]\) window\[STATE_KEY\]\.mediaLayer = mediaLayer;/,
  );
});

test("Canonical CSS themes every required native UI region", () => {
  const requiredFragments = [
    "__DREAM_SELECTOR_LEFT_PANEL__",
    "data-ds-sidebar-group",
    "data-ds-sidebar-row",
    "aria-current=\"page\"",
    ":hover",
    "::-webkit-scrollbar-thumb",
    "data-ds-sidebar-account",
    "data-ds-part=\"header\"",
    "__DREAM_SELECTOR_COMPOSER_CHROME__",
    "data-ds-part=\"dialog\"",
    "data-dream-new-window",
  ];
  for (const fragment of requiredFragments) {
    assert.ok(css.includes(fragment), `missing full UI styling fragment: ${fragment}`);
  }
  assert.match(css, /font-family:\s*var\(--ds-font-body\)/);
  assert.match(css, /font-family:\s*var\(--ds-font-title\)/);
  assert.match(css, /font-family:\s*var\(--ds-font-label\)/);
});

test("Every family themes the home surface, shortcut cards, header and new windows", () => {
  for (const variable of ["--ds-family-hero-glow", "--ds-family-card-highlight", "--ds-family-window-frame"]) {
    assert.ok(css.includes(variable), `missing family effect token: ${variable}`);
  }
  for (const family of [
    "cinematic-cyber", "nature-healing", "warm-editorial",
    "cartoon-stationery", "pixel-retro", "celestial-fantasy",
  ]) assert.match(css, new RegExp(`data-dream-family="${family}"[^}]+--ds-family-hero-glow`));
  for (const fragment of [
    "__DREAM_SELECTOR_HOME_ROUTE__::after",
    "__DREAM_SELECTOR_HOME_SUGGESTIONS__ button::after",
    "[data-ds-part=\"header\"]::after",
    "[data-dream-new-window=\"themed\"] [data-ds-part=\"main\"]",
  ]) assert.ok(css.includes(fragment), `missing themed surface selector: ${fragment}`);
});

test("All decorative layers remain inert", () => {
  for (const selector of ["__DREAM_SELECTOR_LEFT_PANEL__::after", "body::after"]) {
    const start = css.indexOf(`${selector} {\n  content:`);
    assert.notEqual(start, -1, `${selector} must exist`);
    const block = css.slice(start, css.indexOf("}", start) + 1);
    assert.match(block, /pointer-events:\s*none/);
  }
});
