const ID_PATTERN = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const COLOR_PATTERN = /^#[0-9a-f]{6}$/i;
const CONTROL_PATTERN = /[\u0000-\u001f\u007f]/u;

export const THEME_FAMILIES = Object.freeze([
  "cinematic-cyber",
  "nature-healing",
  "warm-editorial",
  "cartoon-stationery",
  "pixel-retro",
  "celestial-fantasy",
]);

export const FONT_PRESETS = Object.freeze([
  "native-sans",
  "rounded",
  "editorial",
  "native-mono",
  "pixel",
]);

export const VISUAL_PRESETS = Object.freeze({
  layout: Object.freeze(["poster-right", "editorial", "stage", "console", "collage", "pixel-platform", "pixel-desktop", "pixel-console"]),
  surface: Object.freeze(["glass", "paper", "metal", "ink", "pixel"]),
  corners: Object.freeze(["cut", "stamp", "round", "tape", "ticket", "pixel"]),
  motion: Object.freeze(["none", "orbit", "petals", "rain", "mist", "sparks", "scan", "ink", "mail", "spotlight", "doodle", "pixel-rain", "cursor", "sonar"]),
  sidebar: Object.freeze(["navigation", "garden", "neon", "maritime", "harbor", "forge", "scroll", "terminal", "station", "blueprint", "aurora", "postal", "setlist", "notebook", "file-tree", "submarine"]),
  composer: Object.freeze(["console", "letter", "terminal", "label", "pixel-console", "workbench", "mixer", "dialog", "sonar"]),
  texture: Object.freeze(["grid", "wash", "scanline", "grain", "droplets", "paper", "dither", "halftone", "vinyl", "crayon"]),
});

const ROOT_KEYS = Object.freeze([
  "schemaVersion", "id", "name", "appearance", "family", "media",
  "typography", "visual", "colors", "art", "risk",
]);
const MEDIA_KEYS = Object.freeze(["poster", "video"]);
const TYPOGRAPHY_KEYS = Object.freeze(["body", "title", "label", "code"]);
const VISUAL_KEYS = Object.freeze(["layout", "surface", "corners", "motion", "sidebar", "composer", "texture"]);
const COLOR_KEYS = Object.freeze(["background", "panel", "panelAlt", "accent", "secondary", "text", "muted", "line"]);
const ART_KEYS = Object.freeze(["focusX", "focusY", "safeArea", "taskMode"]);
const RISK_KEYS = Object.freeze(["status", "note"]);

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function assertRecord(value, label) {
  if (!isRecord(value)) throw new TypeError(`${label} must be an object`);
  return value;
}

function assertExactKeys(value, expected, label) {
  for (const key of expected) {
    if (!Object.hasOwn(value, key)) throw new TypeError(`${label} is missing ${key}`);
  }
  const allowed = new Set(expected);
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) throw new TypeError(`${label} contains unsupported field ${key}`);
  }
}

function assertText(value, label, min, max) {
  if (typeof value !== "string" || CONTROL_PATTERN.test(value)) {
    throw new TypeError(`${label} must be plain text`);
  }
  const normalized = value.trim();
  const length = Array.from(normalized).length;
  if (length < min || length > max) throw new TypeError(`${label} has an invalid length`);
  return normalized;
}

function assertEnum(value, allowed, label) {
  if (!allowed.includes(value)) throw new TypeError(`${label} has an unsupported value`);
  return value;
}

function assertCoordinate(value, label) {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 1) {
    throw new TypeError(`${label} must be between 0 and 1`);
  }
  return value;
}

function assertColor(value, label) {
  if (typeof value !== "string" || !COLOR_PATTERN.test(value)) {
    throw new TypeError(`${label} must be a six-digit hexadecimal color`);
  }
  return value.toLowerCase();
}

function assertPackageName(value, expected, label) {
  if (value !== expected) throw new TypeError(`${label} must be ${expected}`);
  return value;
}

function deepFreeze(value) {
  if (!isRecord(value) && !Array.isArray(value)) return value;
  for (const item of Object.values(value)) deepFreeze(item);
  return Object.freeze(value);
}

export function validateThemeV2(input) {
  const theme = assertRecord(input, "theme");
  assertExactKeys(theme, ROOT_KEYS, "theme");
  if (theme.schemaVersion !== 2) throw new TypeError("theme.schemaVersion must be 2");

  const id = assertText(theme.id, "theme.id", 3, 64);
  if (!ID_PATTERN.test(id)) throw new TypeError("theme.id has an invalid format");

  const media = assertRecord(theme.media, "theme.media");
  const typography = assertRecord(theme.typography, "theme.typography");
  const visual = assertRecord(theme.visual, "theme.visual");
  const colors = assertRecord(theme.colors, "theme.colors");
  const art = assertRecord(theme.art, "theme.art");
  const risk = assertRecord(theme.risk, "theme.risk");
  assertExactKeys(media, MEDIA_KEYS, "theme.media");
  assertExactKeys(typography, TYPOGRAPHY_KEYS, "theme.typography");
  assertExactKeys(visual, VISUAL_KEYS, "theme.visual");
  assertExactKeys(colors, COLOR_KEYS, "theme.colors");
  assertExactKeys(art, ART_KEYS, "theme.art");
  assertExactKeys(risk, RISK_KEYS, "theme.risk");

  const normalized = {
    schemaVersion: 2,
    id,
    name: assertText(theme.name, "theme.name", 1, 80),
    appearance: assertEnum(theme.appearance, ["light", "dark"], "theme.appearance"),
    family: assertEnum(theme.family, THEME_FAMILIES, "theme.family"),
    media: {
      poster: assertPackageName(media.poster, "background.webp", "theme.media.poster"),
      video: media.video === null ? null : assertPackageName(media.video, "background.mp4", "theme.media.video"),
    },
    typography: {
      body: assertEnum(typography.body, FONT_PRESETS, "theme.typography.body"),
      title: assertEnum(typography.title, FONT_PRESETS, "theme.typography.title"),
      label: assertEnum(typography.label, FONT_PRESETS, "theme.typography.label"),
      code: assertEnum(typography.code, FONT_PRESETS, "theme.typography.code"),
    },
    visual: Object.fromEntries(VISUAL_KEYS.map((key) => [
      key,
      assertEnum(visual[key], VISUAL_PRESETS[key], `theme.visual.${key}`),
    ])),
    colors: Object.fromEntries(COLOR_KEYS.map((key) => [key, assertColor(colors[key], `theme.colors.${key}`)])),
    art: {
      focusX: assertCoordinate(art.focusX, "theme.art.focusX"),
      focusY: assertCoordinate(art.focusY, "theme.art.focusY"),
      safeArea: assertEnum(art.safeArea, ["left", "right", "center", "none"], "theme.art.safeArea"),
      taskMode: assertEnum(art.taskMode, ["ambient", "banner", "full", "off"], "theme.art.taskMode"),
    },
    risk: {
      status: assertEnum(risk.status, ["approved", "copyright_review", "reference_only"], "theme.risk.status"),
      note: assertText(risk.note, "theme.risk.note", 0, 240),
    },
  };

  return deepFreeze(normalized);
}
