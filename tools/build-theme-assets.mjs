import { execFile } from "node:child_process";
import fs from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const args = process.argv.slice(2);
const valueOf = (name) => {
  const index = args.indexOf(name);
  if (index < 0 || !args[index + 1]) throw new Error(`Missing ${name}`);
  return args[index + 1];
};
const sourceRoot = path.resolve(valueOf("--source"));
const manifestPath = path.resolve(valueOf("--materials"));
const outputRoot = path.resolve(valueOf("--output"));
const manifest = JSON.parse(await fs.readFile(manifestPath, "utf8"));

const profiles = {
  "cinematic-cyber": { background: "#090d16", panel: "#101827", panelAlt: "#18233a", accent: "#45d8ff", secondary: "#f05ac6", text: "#f1fbff", muted: "#9cb0c2", line: "#31567a", visual: ["console","metal","cut","scan","neon","terminal","scanline"] },
  "nature-healing": { background: "#0d1714", panel: "#15231e", panelAlt: "#1d3028", accent: "#66c59b", secondary: "#e2ae65", text: "#f2fff8", muted: "#a7c0b3", line: "#426b57", visual: ["editorial","ink","stamp","mist","garden","label","paper"] },
  "warm-editorial": { background: "#19140f", panel: "#251e17", panelAlt: "#33281e", accent: "#d7aa68", secondary: "#7ba891", text: "#fff8e9", muted: "#c4b39a", line: "#6e5a3d", visual: ["collage","paper","tape","none","notebook","workbench","grain"] },
  "cartoon-stationery": { background: "#18131d", panel: "#241c2b", panelAlt: "#30243a", accent: "#ee91ba", secondary: "#7bcfd6", text: "#fff8fc", muted: "#cabac8", line: "#765b79", visual: ["poster-right","paper","round","doodle","garden","letter","wash"] },
  "pixel-retro": { background: "#0c0b1a", panel: "#151229", panelAlt: "#211b3c", accent: "#ed5bb5", secondary: "#50d7dd", text: "#fff6ff", muted: "#b5a7c7", line: "#5d477d", visual: ["pixel-desktop","pixel","pixel","pixel-rain","file-tree","pixel-console","dither"] },
  "celestial-fantasy": { background: "#08101f", panel: "#101a31", panelAlt: "#182744", accent: "#78bfff", secondary: "#a783ee", text: "#f4f8ff", muted: "#aab9d3", line: "#405a88", visual: ["poster-right","glass","round","orbit","aurora","console","grain"] },
};

function familyFor(name) {
  if (/像素|马里奥|复古游戏/i.test(name)) return "pixel-retro";
  if (/赛博|霓虹|电竞|都市|蜘蛛|黑客/i.test(name)) return "cinematic-cyber";
  if (/动漫|少女|卡通|插画/i.test(name)) return "cartoon-stationery";
  if (/星空|星瞳|云海|极光|蝴蝶|礼服/i.test(name)) return "celestial-fantasy";
  if (/水面|蓝天|山脉|街景|下雨|车站|日式|店铺|海边|大海/i.test(name)) return "nature-healing";
  return "warm-editorial";
}

async function run(command, commandArgs) {
  return execFileAsync(command, commandArgs, { maxBuffer: 4 * 1024 * 1024 });
}

async function renderPoster(input, output) {
  await run("/usr/local/bin/magick", [
    input, "-auto-orient", "-filter", "Lanczos", "-resize", "3840x2400^",
    "-gravity", "center", "-extent", "3840x2400", "-unsharp", "0x0.75+0.65+0.015",
    "-quality", "88", output,
  ]);
}

async function posterSource(item, themeDir) {
  const input = path.join(sourceRoot, item.sourcePath);
  if (item.kind === "static") return input;
  const thumbnailRoot = path.join(themeDir, ".thumbnail");
  await fs.mkdir(thumbnailRoot);
  await run("/usr/bin/qlmanage", ["-t", "-s", "2400", "-o", thumbnailRoot, input]);
  const generated = path.join(thumbnailRoot, `${item.sourcePath}.png`);
  return generated;
}

for (const item of manifest.items) {
  if (item.status === "duplicate") continue;
  const outputThemeId = `material-${item.id.slice("material-".length)}`;
  const themeDir = path.join(outputRoot, outputThemeId);
  try {
    await fs.rm(themeDir, { recursive: true, force: true });
    await fs.mkdir(themeDir, { recursive: true });
    const source = await posterSource(item, themeDir);
    await renderPoster(source, path.join(themeDir, "background.webp"));
    await run("/usr/local/bin/magick", [path.join(themeDir, "background.webp"), "-resize", "1200x750!", "-quality", "86", path.join(themeDir, "preview.webp")]);

    let videoDisposition = null;
    let video = null;
    if (item.kind === "video") {
      const eligible = item.width >= 2560 && item.height >= 1440;
      if (eligible) {
        try {
          const output = path.join(themeDir, "background.mp4");
          await run("/usr/bin/avconvert", ["--source", path.join(sourceRoot, item.sourcePath), "--preset", "Preset3840x2160", "--output", output, "--replace", "--disableMetadataFilter"]);
          const stat = await fs.stat(output);
          if (stat.size > 80 * 1024 * 1024) throw new Error("4K video exceeds 80 MiB");
          video = "background.mp4";
          videoDisposition = "true-dynamic";
        } catch (error) {
          await fs.rm(path.join(themeDir, "background.mp4"), { force: true });
          videoDisposition = "ambient-reconstruction";
          item.videoFallbackReason = String(error.message).slice(0, 240);
        }
      } else {
        videoDisposition = "ambient-reconstruction";
        item.videoFallbackReason = `source resolution ${item.width}x${item.height} is below dynamic 4K production threshold`;
      }
    }
    await fs.rm(path.join(themeDir, ".thumbnail"), { recursive: true, force: true });
    const family = familyFor(item.sourcePath);
    const profile = profiles[family];
    const [layout, surface, corners, motion, sidebar, composer, texture] = profile.visual;
    const theme = {
      schemaVersion: 2,
      id: outputThemeId,
      name: path.parse(item.sourcePath).name.slice(0, 80),
      appearance: "dark",
      family,
      media: { poster: "background.webp", video },
      typography: { body: "native-sans", title: family === "pixel-retro" ? "pixel" : family === "warm-editorial" ? "editorial" : family === "cartoon-stationery" ? "rounded" : "native-sans", label: family === "pixel-retro" ? "pixel" : "native-sans", code: "native-mono" },
      visual: { layout, surface, corners, motion: video ? "none" : motion, sidebar, composer, texture },
      colors: Object.fromEntries(Object.entries(profile).filter(([key]) => key !== "visual")),
      art: { focusX: 0.7, focusY: 0.48, safeArea: "left", taskMode: "full" },
      risk: { status: item.risk.status === "copyright_review" ? "copyright_review" : "reference_only", note: item.risk.note },
    };
    await fs.writeFile(path.join(themeDir, "theme.json"), `${JSON.stringify(theme, null, 2)}\n`);
    item.status = item.risk.status === "copyright_review" ? "copyright_review" : "ready";
    item.outputThemeId = outputThemeId;
    item.localCandidatePath = path.relative(path.dirname(manifestPath), themeDir);
    item.processing = {
      poster: "structured-upscale-3840x2400",
      preview: "1200x750",
      sourceSha256: item.sha256,
    };
    if (item.kind === "video") item.videoDisposition = videoDisposition;
    delete item.failureReason;
    process.stdout.write(`built ${outputThemeId}\n`);
  } catch (error) {
    item.status = "failed";
    item.failureReason = String(error.message).slice(0, 500);
    item.outputThemeId = null;
    process.stdout.write(`failed ${outputThemeId}: ${item.failureReason}\n`);
  }
}

for (const item of manifest.items.filter((candidate) => candidate.status === "duplicate")) {
  const canonical = manifest.items.find((candidate) => candidate.id === item.canonicalId);
  item.outputThemeId = canonical?.outputThemeId ?? null;
}
await fs.writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
