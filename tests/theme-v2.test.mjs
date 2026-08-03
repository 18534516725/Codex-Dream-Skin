import assert from "node:assert/strict";
import test from "node:test";

import {
  FONT_PRESETS,
  THEME_FAMILIES,
  VISUAL_PRESETS,
  validateThemeV2,
} from "../themes/theme-v2.mjs";

function validTheme(overrides = {}) {
  return {
    schemaVersion: 2,
    id: "sakura-signal",
    name: "樱花信使",
    appearance: "dark",
    family: "cartoon-stationery",
    media: { poster: "background.webp", video: null },
    typography: {
      body: "native-sans",
      title: "rounded",
      label: "rounded",
      code: "native-mono",
    },
    visual: {
      layout: "poster-right",
      surface: "paper",
      corners: "stamp",
      motion: "petals",
      sidebar: "garden",
      composer: "letter",
      texture: "wash",
    },
    colors: {
      background: "#19141f",
      panel: "#211a29",
      panelAlt: "#2a2134",
      accent: "#e897be",
      secondary: "#a689e8",
      text: "#fff8fc",
      muted: "#cabdca",
      line: "#735b7d",
    },
    art: { focusX: 0.72, focusY: 0.45, safeArea: "left", taskMode: "ambient" },
    risk: { status: "approved", note: "original" },
    ...overrides,
  };
}

test("Theme V2 normalizes the complete reviewed contract", () => {
  const theme = validateThemeV2(validTheme());
  assert.equal(theme.id, "sakura-signal");
  assert.equal(theme.schemaVersion, 2);
  assert.equal(theme.media.poster, "background.webp");
  assert.equal(theme.media.video, null);
  assert.equal(theme.risk.status, "approved");
  assert.equal(Object.isFrozen(theme), true);
});

test("Theme V2 exports closed family, typography and visual enums", () => {
  assert.deepEqual(THEME_FAMILIES, [
    "cinematic-cyber",
    "nature-healing",
    "warm-editorial",
    "cartoon-stationery",
    "pixel-retro",
    "celestial-fantasy",
  ]);
  assert.ok(FONT_PRESETS.includes("native-sans"));
  assert.ok(FONT_PRESETS.includes("native-mono"));
  assert.ok(VISUAL_PRESETS.motion.includes("petals"));
  assert.ok(VISUAL_PRESETS.sidebar.includes("garden"));
});

test("Theme V2 rejects traversal, URLs and unsupported keys", () => {
  assert.throws(
    () => validateThemeV2(validTheme({ id: "../../bad" })),
    /theme\.id/,
  );
  assert.throws(
    () => validateThemeV2(validTheme({ media: { poster: "https://bad.example/a.webp", video: null } })),
    /media\.poster/,
  );
  assert.throws(
    () => validateThemeV2({ ...validTheme(), arbitraryScript: "alert(1)" }),
    /unsupported field arbitraryScript/,
  );
});

test("Theme V2 accepts only local poster and optional H.264 package filename", () => {
  const dynamic = validateThemeV2(validTheme({
    media: { poster: "background.webp", video: "background.mp4" },
  }));
  assert.equal(dynamic.media.video, "background.mp4");

  assert.throws(
    () => validateThemeV2(validTheme({ media: { poster: "background.webp", video: "clip.mov" } })),
    /media\.video/,
  );
  assert.throws(
    () => validateThemeV2(validTheme({ media: { poster: "../background.webp", video: null } })),
    /media\.poster/,
  );
});

test("Theme V2 rejects invalid colors, focus coordinates and risk states", () => {
  assert.throws(
    () => validateThemeV2(validTheme({
      colors: { ...validTheme().colors, accent: "url(https://bad.example)" },
    })),
    /colors\.accent/,
  );
  assert.throws(
    () => validateThemeV2(validTheme({ art: { ...validTheme().art, focusX: 1.5 } })),
    /art\.focusX/,
  );
  assert.throws(
    () => validateThemeV2(validTheme({ risk: { status: "public-anyway", note: "" } })),
    /risk\.status/,
  );
});
