import fs from "node:fs/promises";
import { constants as fsConstants } from "node:fs";
import { randomBytes } from "node:crypto";
import path from "node:path";

export const APPEARANCE_SCHEMA_VERSION = 1;
export const APPEARANCE_FONTS = Object.freeze([
  "native", "clear", "rounded", "editorial", "condensed", "humanist", "code", "pixel",
]);
export const DEFAULT_APPEARANCE_SETTINGS = Object.freeze({
  backgroundVisibility: 78,
  sidebarOpacity: 78,
  contentOpacity: 72,
  font: "native",
  fontSize: 15,
  contrast: 88,
});

const ENVELOPE_FIELDS = ["schemaVersion", "settings", "skinId"];
const SETTING_FIELDS = [
  "backgroundVisibility", "contentOpacity", "contrast", "font", "fontSize", "sidebarOpacity",
];
const LIMITS = Object.freeze({
  backgroundVisibility: [0, 100],
  sidebarOpacity: [20, 100],
  contentOpacity: [20, 100],
  fontSize: [12, 20],
  contrast: [60, 100],
});

function hasExactFields(value, fields) {
  return value && typeof value === "object" && !Array.isArray(value) &&
    Object.keys(value).sort().join("\0") === [...fields].sort().join("\0");
}

export function validateAppearanceEnvelope(input, approvedSkinIds) {
  if (!hasExactFields(input, ENVELOPE_FIELDS)) throw new Error("Appearance envelope has invalid fields");
  if (input.schemaVersion !== APPEARANCE_SCHEMA_VERSION) throw new Error("Appearance schema version is invalid");
  if (typeof input.skinId !== "string" || !approvedSkinIds?.has(input.skinId)) {
    throw new Error("Appearance skin is not approved");
  }
  if (!hasExactFields(input.settings, SETTING_FIELDS)) throw new Error("Appearance settings have invalid fields");
  const settings = {};
  for (const [key, [minimum, maximum]] of Object.entries(LIMITS)) {
    const value = input.settings[key];
    if (!Number.isInteger(value) || value < minimum || value > maximum) {
      throw new Error(`Appearance ${key} is invalid`);
    }
    settings[key] = value;
  }
  if (!APPEARANCE_FONTS.includes(input.settings.font)) throw new Error("Appearance font is invalid");
  settings.font = input.settings.font;
  return { schemaVersion: APPEARANCE_SCHEMA_VERSION, skinId: input.skinId, settings };
}

export function toRuntimeAppearance(settings) {
  return {
    backgroundVisibility: settings.backgroundVisibility / 100,
    sidebarOpacity: settings.sidebarOpacity / 100,
    contentOpacity: settings.contentOpacity / 100,
    font: settings.font,
    fontSize: Number((settings.fontSize / 15).toFixed(4)),
    contrast: settings.contrast / 100,
  };
}

async function ensureRegularOrMissing(filePath, maximumBytes) {
  try {
    const stat = await fs.lstat(filePath);
    if (!stat.isFile() || stat.isSymbolicLink() || stat.size > maximumBytes) {
      throw new Error("Appearance settings file is unsafe");
    }
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
}

async function atomicJsonWrite(filePath, value) {
  const parent = path.dirname(filePath);
  await fs.mkdir(parent, { recursive: true, mode: 0o700 });
  await ensureRegularOrMissing(filePath, 256 * 1024);
  const temporary = path.join(parent, `.${path.basename(filePath)}.${randomBytes(12).toString("hex")}.tmp`);
  let handle;
  try {
    handle = await fs.open(temporary, fsConstants.O_CREAT | fsConstants.O_EXCL | fsConstants.O_WRONLY, 0o600);
    await handle.writeFile(`${JSON.stringify(value, null, 2)}\n`, "utf8");
    await handle.sync();
    await handle.close();
    handle = null;
    await fs.rename(temporary, filePath);
    await fs.chmod(filePath, 0o600);
  } finally {
    if (handle) await handle.close().catch(() => {});
    await fs.rm(temporary, { force: true }).catch(() => {});
  }
}

export class AppearanceSettingsStore {
  constructor({ stateRoot, approvedSkinIds }) {
    if (!path.isAbsolute(stateRoot)) throw new Error("Appearance state root must be absolute");
    this.stateRoot = path.resolve(stateRoot);
    this.approvedSkinIds = approvedSkinIds;
    this.storePath = path.join(this.stateRoot, "appearance-by-skin.json");
    this.activePath = path.join(this.stateRoot, "appearance.json");
    this.writeChain = Promise.resolve();
  }

  async readStore() {
    await ensureRegularOrMissing(this.storePath, 256 * 1024);
    try {
      const parsed = JSON.parse(await fs.readFile(this.storePath, "utf8"));
      if (parsed?.schemaVersion !== APPEARANCE_SCHEMA_VERSION || !parsed.skins ||
        typeof parsed.skins !== "object" || Array.isArray(parsed.skins)) return { schemaVersion: 1, skins: {} };
      return parsed;
    } catch (error) {
      if (error.code === "ENOENT" || error instanceof SyntaxError) return { schemaVersion: 1, skins: {} };
      throw error;
    }
  }

  async put(input) {
    const envelope = validateAppearanceEnvelope(input, this.approvedSkinIds);
    const write = this.writeChain.then(async () => {
      const current = await this.readStore();
      const next = { schemaVersion: APPEARANCE_SCHEMA_VERSION, skins: { ...current.skins, [envelope.skinId]: envelope.settings } };
      await atomicJsonWrite(this.storePath, next);
      return envelope;
    });
    this.writeChain = write.catch(() => {});
    return write;
  }

  async get(skinId) {
    if (!this.approvedSkinIds.has(skinId)) throw new Error("Appearance skin is not approved");
    const current = await this.readStore();
    const candidate = current.skins[skinId];
    if (!candidate) return { schemaVersion: 1, skinId, settings: { ...DEFAULT_APPEARANCE_SETTINGS } };
    return validateAppearanceEnvelope({ schemaVersion: 1, skinId, settings: candidate }, this.approvedSkinIds);
  }

  async materialize(skinId) {
    const envelope = await this.get(skinId);
    await atomicJsonWrite(this.activePath, toRuntimeAppearance(envelope.settings));
    return envelope;
  }
}
