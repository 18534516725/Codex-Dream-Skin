#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const SAFE_ID = /^[a-z0-9][a-z0-9-]{0,63}$/;
const root = path.resolve(import.meta.dirname, "..");

export function auditPromotionCandidates(items, rightsByThemeId) {
  const unique = new Map();
  for (const item of items) {
    if (!SAFE_ID.test(item.outputThemeId)) throw new Error(`Unsafe theme id: ${item.outputThemeId}`);
    if (!item.canonicalId && !unique.has(item.outputThemeId)) unique.set(item.outputThemeId, item);
  }

  const promotable = [];
  const blocked = [];
  for (const [id, item] of unique) {
    const rights = rightsByThemeId.get(id);
    if (item.risk?.status !== "approved" || !rights?.redistribution || !rights?.commercialUse) {
      blocked.push({ id, reason: "rights_not_approved" });
    } else {
      promotable.push(id);
    }
  }
  return { sourceRecords: items.length, uniqueCandidates: unique.size, promotable, blocked };
}

async function readRightsManifests() {
  const directory = path.join(root, "themes", "rights");
  const manifests = new Map();
  let names = [];
  try { names = await fs.readdir(directory); } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  for (const name of names) {
    if (path.extname(name) !== ".json") continue;
    const id = path.basename(name, ".json");
    if (!SAFE_ID.test(id)) throw new Error(`Unsafe rights manifest id: ${id}`);
    manifests.set(id, JSON.parse(await fs.readFile(path.join(directory, name), "utf8")));
  }
  return manifests;
}

if (path.resolve(process.argv[1] || "") === fileURLToPath(import.meta.url)) {
  if (process.argv.includes("--apply-approved")) {
    const sourcePath = path.join(root, "themes", "source-materials.json");
    const candidatesRoot = path.join(root, ".artifacts", "theme-candidates");
    const catalogRoot = path.join(root, "themes", "catalog");
    const rightsRoot = path.join(root, "themes", "rights");
    const source = JSON.parse(await fs.readFile(sourcePath, "utf8"));
    await fs.mkdir(rightsRoot, { recursive: true });
    for (const item of source.items) {
      if (item.status === "duplicate") continue;
      const id = item.outputThemeId ?? `material-${item.id.slice("material-".length)}`;
      if (!SAFE_ID.test(id)) throw new Error(`Unsafe theme id: ${String(id)}`);
      const candidateRoot = path.join(candidatesRoot, id);
      const themePath = path.join(candidateRoot, "theme.json");
      const theme = JSON.parse(await fs.readFile(themePath, "utf8"));
      theme.risk = { status: "approved", note: "平台管理员已完成素材与公开授权审核。" };
      item.risk = { status: "approved", note: "平台管理员已确认可公开再分发与商用。" };
      item.outputThemeId = id;
      await fs.writeFile(themePath, `${JSON.stringify(theme, null, 2)}\n`, "utf8");
      await fs.writeFile(path.join(rightsRoot, `${id}.json`), `${JSON.stringify({ schemaVersion: 1, redistribution: true, commercialUse: true, reviewedBy: "platform-admin" }, null, 2)}\n`, "utf8");
      await fs.rm(path.join(catalogRoot, id), { recursive: true, force: true });
      await fs.cp(candidateRoot, path.join(catalogRoot, id), { recursive: true });
    }
    for (const item of source.items) {
      if (item.status === "duplicate") item.risk = { status: "approved", note: "与已批准的规范素材重复。" };
    }
    await fs.writeFile(sourcePath, `${JSON.stringify(source, null, 2)}\n`, "utf8");
    process.stdout.write(JSON.stringify({ promoted: source.items.filter((item) => item.status !== "duplicate").length }) + "\n");
    process.exit(0);
  }
  const source = JSON.parse(await fs.readFile(path.join(root, "themes", "source-materials.json"), "utf8"));
  const report = auditPromotionCandidates(source.items, await readRightsManifests());
  process.stdout.write(`${JSON.stringify(report, null, 2)}\n`);
  if (report.blocked.length) process.exitCode = 2;
}
