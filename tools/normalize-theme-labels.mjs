import fs from "node:fs/promises";
import path from "node:path";

const root = path.resolve(import.meta.dirname, "..");
const catalogDirectory = path.join(root, "themes", "catalog");

const specialLabels = new Map([
  ["material-1a8850341d81-48ef8f75", "街角小铺"],
  ["material-35518c15db60-3fb88cb5", "暗影蛛侠"],
  ["material-3d14a72399f4-5100b418", "蝶舞黄昏"],
  ["material-5c8675795ebb-f69a229a", "云山晴空"],
  ["material-65a457280941-bb73aad1", "冰火长离"],
  ["material-702fed2aca8c-9c0787b7", "云海漩涡"],
  ["material-774fd232d777-a59a0c1b", "水面小熊"],
  ["material-7b9b6ff2c4f6-28fc0b99", "雨站绿意"],
  ["material-983423060f57-cadf7a6b", "雪山街景"],
  ["material-a17a308d35d3-21aba190", "霓虹少女"],
  ["material-a53f83b337b5-218c740f", "像素蘑菇"],
  ["material-a5f713f94418-15fba88c", "落日街道"],
  ["material-ab048e4644d4-3eb7aa3b", "星瞳剑影"],
  ["material-acccc3326809-e9e74869", "居家少女"],
  ["material-b388e6005506-09c334f1", "水中星梦"],
  ["material-c915acac96a5-66541347", "赛博夜城"],
  ["material-d3c6b69bacc3-a605f3bf", "像素猩猩"],
  ["material-d430abd95534-a13d761c", "雨天小铺"],
  ["material-dde38c0aaf98-86f2e704", "霓虹客厅"],
  ["material-df6388daee46-e3486a16", "深蓝礼服"],
  ["material-e8f2d89ab026-1e6a137e", "星眸少女"],
  ["material-ebab83397bde-2d3696f1", "霓虹夜城"],
  ["material-ecccbb789992-51cc5983", "蜘蛛宇宙"],
  ["material-fd47543151e3-e1f77f50", "海边芙宁"],
]);

const familyPrefixes = {
  "warm-editorial": "暖景",
  "cartoon-stationery": "童趣",
  "cinematic-cyber": "霓虹",
  "celestial-fantasy": "星梦",
  "nature-healing": "自然",
  "pixel-retro": "像素",
};

const entries = (await fs.readdir(catalogDirectory, { withFileTypes: true }))
  .filter((entry) => entry.isDirectory() && entry.name.startsWith("material-"))
  .sort((left, right) => left.name.localeCompare(right.name, "en"));
const counters = new Map();

for (const entry of entries) {
  const themePath = path.join(catalogDirectory, entry.name, "theme.json");
  const theme = JSON.parse(await fs.readFile(themePath, "utf8"));
  const prefix = familyPrefixes[theme.family];
  if (!prefix) throw new Error(`Unsupported material theme family: ${theme.family}`);
  const ordinal = (counters.get(theme.family) ?? 0) + 1;
  counters.set(theme.family, ordinal);
  const name = specialLabels.get(theme.id) ?? `${prefix}${String(ordinal).padStart(2, "0")}`;
  if (Array.from(name).length > 5) throw new Error(`Label exceeds five characters: ${theme.id}`);
  theme.name = name;
  await fs.writeFile(themePath, `${JSON.stringify(theme, null, 2)}\n`, "utf8");
}

process.stdout.write(`normalized ${entries.length} material theme labels\n`);
