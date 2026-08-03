#!/usr/bin/env node

import crypto from "node:crypto";
import fs from "node:fs/promises";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const materialsPath = path.join(root, "themes", "source-materials.json");
const candidatesRoot = path.join(root, ".artifacts", "theme-candidates");
const outputPath = path.join(root, "themes", "material-review-catalog.json");

const sha256 = async (filePath) => crypto.createHash("sha256").update(await fs.readFile(filePath)).digest("hex");
const materials = JSON.parse(await fs.readFile(materialsPath, "utf8"));
const uniqueItems = materials.items.filter((item) => item.status !== "duplicate");

const items = [];
for (const source of uniqueItems) {
  const candidateDir = path.join(candidatesRoot, source.outputThemeId);
  const themePath = path.join(candidateDir, "theme.json");
  const posterPath = path.join(candidateDir, "background.webp");
  const previewPath = path.join(candidateDir, "preview.webp");
  const theme = JSON.parse(await fs.readFile(themePath, "utf8"));
  const videoPath = path.join(candidateDir, "background.mp4");
  let video = null;
  try {
    const stat = await fs.stat(videoPath);
    video = { file: "background.mp4", bytes: stat.size, sha256: await sha256(videoPath) };
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
  }

  const [posterStat, previewStat] = await Promise.all([fs.stat(posterPath), fs.stat(previewPath)]);
  items.push({
    id: source.outputThemeId,
    sourceId: source.id,
    sourceLabel: source.sourcePath,
    sourceSha256: source.sha256,
    status: source.status,
    publication: source.risk?.status === "approved" ? "public" : source.risk?.status === "unreviewed" ? "admin_review_only" : "blocked_pending_rights_review",
    mediaMode: source.videoDisposition ?? "static",
    title: theme.name ?? theme.title ?? source.outputThemeId,
    family: theme.family ?? null,
    poster: { file: "background.webp", width: 3840, height: 2400, bytes: posterStat.size, sha256: await sha256(posterPath) },
    preview: { file: "preview.webp", width: 1200, height: 750, bytes: previewStat.size, sha256: await sha256(previewPath) },
    video,
  });
}

items.sort((a, b) => a.sourceLabel.localeCompare(b.sourceLabel, "zh-CN"));
const output = {
  schemaVersion: 1,
  sourceCount: materials.items.length,
  uniqueThemeCount: items.length,
  duplicateCount: materials.items.length - items.length,
  dynamicCount: items.filter((item) => item.video).length,
  ambientReconstructionCount: items.filter((item) => item.mediaMode === "ambient-reconstruction").length,
  staticCount: items.filter((item) => item.mediaMode === "static").length,
  publicThemeCount: items.filter((item) => item.publication === "public").length,
  note: "已通过授权审核的候选包可进入正式目录；其余候选仅保留在管理员审核队列。",
  items,
};

await fs.writeFile(outputPath, `${JSON.stringify(output, null, 2)}\n`);
console.log(JSON.stringify({ output: path.relative(root, outputPath), themes: items.length }));
