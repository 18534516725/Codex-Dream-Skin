import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const validator = path.join(root, "runtime", "theme-package-validator.mjs");
const posterFixture = path.join(root, "docs", "images", "site-studio-zh.webp");
const tempRoot = await fs.mkdtemp("/tmp/dream-skin-v2-package-");

function run(args) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [validator, ...args], { stdio: ["ignore", "pipe", "pipe"] });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.once("error", reject);
    child.once("close", (code) => {
      if (code === 0) resolve({ stdout, stderr });
      else reject(new Error(stderr || stdout || `validator exited ${code}`));
    });
  });
}

function json(value) {
  return Buffer.from(`${JSON.stringify(value, null, 2)}\n`);
}

function entry(name, mediaType, bytes) {
  return {
    path: name,
    mediaType,
    bytes: bytes.length,
    sha256: createHash("sha256").update(bytes).digest("hex"),
  };
}

async function makePackage(name, { corruptVideo = false } = {}) {
  const source = path.join(tempRoot, name);
  await fs.mkdir(source);
  const poster = await fs.readFile(posterFixture);
  const video = corruptVideo
    ? Buffer.from("not-an-mp4")
    : Buffer.concat([
      Buffer.from([0, 0, 0, 24]),
      Buffer.from("ftypisom"),
      Buffer.from([0, 0, 0, 0]),
      Buffer.from("isomavc1"),
    ]);
  const css = Buffer.from('[data-ds-part="root"] { color: var(--ds-theme-color-text); }\n');
  const theme = json({
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
  });
  const files = [
    entry("theme.json", "application/json", theme),
    entry("background.webp", "image/webp", poster),
    entry("background.mp4", "video/mp4", video),
    entry("theme.css", "text/css", css),
  ];
  const manifest = json({
    packageVersion: 1,
    themeId: "dynamic-sakura",
    version: "2.0.0",
    skinApiVersion: 2,
    minClientVersion: "1.6.0",
    platforms: ["macos", "windows"],
    capabilities: ["background", "tokens", "safe-css", "dynamic-background"],
    publisher: { id: "dreamskin-studio", displayName: "DreamSkin Studio" },
    license: "CC0-1.0",
    provenance: { aiGenerated: false, summary: "Theme V2 package test." },
    files,
    createdAt: "2026-08-03T00:00:00Z",
  });
  await Promise.all([
    fs.writeFile(path.join(source, "manifest.json"), manifest),
    fs.writeFile(path.join(source, "theme.json"), theme),
    fs.writeFile(path.join(source, "background.webp"), poster),
    fs.writeFile(path.join(source, "background.mp4"), video),
    fs.writeFile(path.join(source, "theme.css"), css),
  ]);
  return source;
}

try {
  const source = await makePackage("valid");
  for (const platform of ["macos", "windows"]) {
    const stage = path.join(tempRoot, `stage-${platform}`);
    await fs.mkdir(stage);
    const result = await run([
      "--source", source,
      "--stage", stage,
      "--platform", platform,
      "--client-version", "1.6.0",
    ]);
    assert.deepEqual(JSON.parse(result.stdout), {
      format: "official",
      image: "background.webp",
      video: "background.mp4",
      safeCssStatus: "validated",
      signatureIgnored: false,
    });
    assert.deepEqual((await fs.readdir(stage)).sort(), [
      "background.mp4", "background.webp", "manifest.json", "theme.css", "theme.json",
    ]);
  }

  const corrupt = await makePackage("corrupt", { corruptVideo: true });
  const stage = path.join(tempRoot, "stage-corrupt");
  await fs.mkdir(stage);
  await assert.rejects(
    run(["--source", corrupt, "--stage", stage, "--platform", "macos", "--client-version", "1.6.0"]),
    /background\.mp4 content is not a bounded H\.264 MP4/,
  );
  assert.deepEqual(await fs.readdir(stage), []);
} finally {
  await fs.rm(tempRoot, { recursive: true, force: true });
}
