import { createHash } from "node:crypto";
import { execFile } from "node:child_process";
import fs from "node:fs/promises";
import { createReadStream } from "node:fs";
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
const outputPath = path.resolve(valueOf("--output"));
const supportedExtensions = new Set([".png", ".jpg", ".jpeg", ".webp", ".mp4", ".mov"]);
const copyrightTerms = /蜘蛛侠|漫威|马里奥|芙宁娜|遐蝶|长离|鸣潮|超级英雄/i;

async function sha256(filePath) {
  const hash = createHash("sha256");
  for await (const chunk of createReadStream(filePath)) hash.update(chunk);
  return hash.digest("hex");
}

function actualFormat(bytes) {
  if (bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))) return "png";
  if (bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "jpeg";
  if (bytes.subarray(0, 4).toString("ascii") === "RIFF" && bytes.subarray(8, 12).toString("ascii") === "WEBP") return "webp";
  if (bytes.subarray(4, 8).toString("ascii") === "ftyp") return "mp4";
  throw new Error("Unsupported media signature");
}

function pngSize(bytes) {
  return bytes.length >= 24 ? [bytes.readUInt32BE(16), bytes.readUInt32BE(20)] : [null, null];
}

function jpegSize(bytes) {
  let offset = 2;
  while (offset + 9 < bytes.length) {
    if (bytes[offset] !== 0xff) { offset += 1; continue; }
    const marker = bytes[offset + 1];
    if ([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].includes(marker)) {
      return [bytes.readUInt16BE(offset + 7), bytes.readUInt16BE(offset + 5)];
    }
    if (marker === 0xd8 || marker === 0xd9) { offset += 2; continue; }
    const length = bytes.readUInt16BE(offset + 2);
    if (length < 2) break;
    offset += length + 2;
  }
  return [null, null];
}

function uint24LE(bytes, offset) {
  return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16);
}

function webpSize(bytes) {
  const kind = bytes.subarray(12, 16).toString("ascii");
  if (kind === "VP8X" && bytes.length >= 30) return [uint24LE(bytes, 24) + 1, uint24LE(bytes, 27) + 1];
  if (kind === "VP8 " && bytes.length >= 30) return [bytes.readUInt16LE(26) & 0x3fff, bytes.readUInt16LE(28) & 0x3fff];
  if (kind === "VP8L" && bytes.length >= 25) {
    const [b1, b2, b3, b4] = [bytes[21], bytes[22], bytes[23], bytes[24]];
    return [1 + (((b2 & 0x3f) << 8) | b1), 1 + (((b4 & 0x0f) << 10) | (b3 << 2) | ((b2 & 0xc0) >> 6))];
  }
  return [null, null];
}

async function imageMetadata(filePath, format) {
  const bytes = await fs.readFile(filePath);
  const [width, height] = format === "png" ? pngSize(bytes)
    : format === "jpeg" ? jpegSize(bytes) : webpSize(bytes);
  return { width, height, durationSeconds: null };
}

async function mdlsValue(filePath, key) {
  try {
    const { stdout } = await execFileAsync("/usr/bin/mdls", ["-raw", "-name", key, filePath]);
    const value = stdout.trim();
    if (!value || value === "(null)") return null;
    const number = Number(value);
    return Number.isFinite(number) ? number : null;
  } catch {
    return null;
  }
}

async function videoMetadata(filePath) {
  const [width, height, durationSeconds] = await Promise.all([
    mdlsValue(filePath, "kMDItemPixelWidth"),
    mdlsValue(filePath, "kMDItemPixelHeight"),
    mdlsValue(filePath, "kMDItemDurationSeconds"),
  ]);
  return {
    width: Number.isInteger(width) ? width : null,
    height: Number.isInteger(height) ? height : null,
    durationSeconds,
  };
}

function statusFor(item) {
  if (copyrightTerms.test(item.sourcePath)) return "copyright_review";
  if (!item.width || !item.height || item.width < 1920 || item.height < 1080) return "repairable";
  return "ready_source";
}

async function loadPrevious() {
  try {
    const parsed = JSON.parse(await fs.readFile(outputPath, "utf8"));
    return new Map((parsed.items ?? []).map((item) => [item.sourcePath, item]));
  } catch (error) {
    if (error.code === "ENOENT") return new Map();
    throw error;
  }
}

const sourceStat = await fs.stat(sourceRoot);
if (!sourceStat.isDirectory()) throw new Error("--source must be a directory");
const previous = await loadPrevious();
const names = (await fs.readdir(sourceRoot, { withFileTypes: true }))
  .filter((entry) => entry.isFile() && supportedExtensions.has(path.extname(entry.name).toLowerCase()))
  .map((entry) => entry.name)
  .sort((left, right) => left.localeCompare(right, "zh-CN"));

const items = [];
for (const name of names) {
  const filePath = path.join(sourceRoot, name);
  const handle = await fs.open(filePath, "r");
  let head;
  try {
    head = Buffer.alloc(64);
    const { bytesRead } = await handle.read(head, 0, head.length, 0);
    head = head.subarray(0, bytesRead);
  } finally {
    await handle.close();
  }
  const format = actualFormat(head);
  const stat = await fs.stat(filePath);
  const digest = await sha256(filePath);
  const metadata = format === "mp4" ? await videoMetadata(filePath) : await imageMetadata(filePath, format);
  const basenameDigest = createHash("sha256").update(path.parse(name).name.normalize("NFKC").toLowerCase()).digest("hex");
  const prior = previous.get(name);
  const item = {
    id: `material-${digest.slice(0, 12)}-${basenameDigest.slice(0, 8)}`,
    sourcePath: name,
    sourceExtension: path.extname(name).slice(1).toLowerCase(),
    kind: format === "mp4" ? "video" : "static",
    actualFormat: format,
    bytes: stat.size,
    sha256: digest,
    width: metadata.width,
    height: metadata.height,
    durationSeconds: metadata.durationSeconds,
    status: "ready_source",
    canonicalId: null,
    risk: {
      status: copyrightTerms.test(name) ? "copyright_review" : "unreviewed",
      note: prior?.risk?.note ?? (copyrightTerms.test(name) ? "可能包含第三方角色或品牌元素，仅限管理员审查。" : "待人工确认来源与公开授权。"),
    },
  };
  item.status = statusFor(item);
  items.push(item);
}

const byHash = new Map();
for (const item of items) {
  const canonical = byHash.get(item.sha256);
  if (!canonical) byHash.set(item.sha256, item);
  else {
    item.status = "duplicate";
    item.canonicalId = canonical.id;
  }
}

const newestMtime = Math.max(...await Promise.all(names.map(async (name) => (await fs.stat(path.join(sourceRoot, name))).mtimeMs)));
const manifest = {
  schemaVersion: 1,
  sourceCount: items.length,
  generatedFrom: path.basename(sourceRoot),
  sourceSnapshotAt: new Date(newestMtime).toISOString(),
  items,
};
await fs.mkdir(path.dirname(outputPath), { recursive: true });
await fs.writeFile(outputPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
process.stdout.write(`${JSON.stringify({ sourceCount: items.length, duplicates: items.filter((item) => item.status === "duplicate").length })}\n`);
