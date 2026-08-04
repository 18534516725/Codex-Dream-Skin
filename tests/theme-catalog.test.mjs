import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import test from "node:test";

import { validateThemeV2 } from "../themes/theme-v2.mjs";

const root = path.resolve(import.meta.dirname, "..");
const catalog = JSON.parse(await fs.readFile(path.join(root, "themes", "catalog.json"), "utf8"));

test("generated theme catalog is strict, unique and cross-platform", () => {
  assert.equal(catalog.schemaVersion, 2);
  assert.equal(catalog.items.length, 87);
  assert.equal(new Set(catalog.items.map((item) => item.id)).size, 87);
  for (const item of catalog.items) {
    assert.equal(validateThemeV2(item.theme).id, item.id);
    assert.deepEqual(item.platforms, ["macos", "windows"]);
    assert.match(item.hashes.theme, /^[a-f0-9]{64}$/);
    assert.match(item.hashes.poster, /^[a-f0-9]{64}$/);
  }
});

test("canonical theme names are concise home labels", () => {
  for (const item of catalog.items) {
    assert.ok(Array.from(item.name).length <= 5, `${item.id} name must be at most five characters`);
    assert.equal(item.theme.name, item.name, `${item.id} embedded theme name must match its catalog label`);
    assert.doesNotMatch(item.name, /(?:壁纸|背景|动态|静态|视频|图片|[234]k)/iu, `${item.id} must not expose source marketing copy`);
  }

  assert.equal(
    catalog.items.find((item) => item.id === "material-ebab83397bde-2d3696f1")?.name,
    "霓虹夜城",
  );
  assert.equal(
    catalog.items.find((item) => item.id === "material-df6388daee46-e3486a16")?.name,
    "深蓝礼服",
  );
});
