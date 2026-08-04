import assert from "node:assert/strict";
import fs from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { request as httpRequest } from "node:http";
import { createAppearanceBridge } from "../runtime/appearance-bridge.mjs";
import {
  APPEARANCE_FONTS,
  AppearanceSettingsStore,
  toRuntimeAppearance,
  validateAppearanceEnvelope,
} from "../runtime/appearance-settings.mjs";

const approved = new Set(["rain", "sakura"]);
const baseSettings = Object.freeze({
  backgroundVisibility: 78,
  sidebarOpacity: 20,
  contentOpacity: 72,
  font: "native",
  fontSize: 15,
  contrast: 88,
  textColor: "",
});
const envelope = (skinId, overrides = {}) => ({
  schemaVersion: 1,
  skinId,
  settings: { ...baseSettings, ...overrides },
});

function request(server, method, pathname, { origin, challenge, body } = {}) {
  const address = server.address();
  const serialized = body === undefined ? null : JSON.stringify(body);
  return new Promise((resolve, reject) => {
    const req = httpRequest({
      host: "127.0.0.1",
      port: address.port,
      path: pathname,
      method,
      headers: {
        ...(origin ? { Origin: origin } : {}),
        ...(challenge ? { "x-dreamskin-challenge": challenge } : {}),
        ...(serialized ? { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(serialized) } : {}),
      },
    }, (response) => {
      let source = "";
      response.setEncoding("utf8");
      response.on("data", (chunk) => { source += chunk; });
      response.on("end", () => resolve({
        status: response.statusCode,
        headers: response.headers,
        body: source ? JSON.parse(source) : null,
      }));
    });
    req.on("error", reject);
    if (serialized) req.end(serialized);
    else req.end();
  });
}

test("accepts every preview font and converts settings to runtime units", () => {
  for (const font of APPEARANCE_FONTS) {
    assert.equal(validateAppearanceEnvelope(envelope("rain", { font }), approved).settings.font, font);
  }
  assert.deepEqual(toRuntimeAppearance(envelope("rain", {
    backgroundVisibility: 0,
    sidebarOpacity: 100,
    contentOpacity: 20,
    font: "editorial",
    fontSize: 12,
    contrast: 60,
    textColor: "#123456",
  }).settings), {
    backgroundVisibility: 0,
    sidebarOpacity: 1,
    contentOpacity: 0.2,
    font: "editorial",
    fontSize: 0.8,
    contrast: 0.6,
    textColor: "#123456",
  });
});

test("rejects unknown, missing, non-integer and out-of-range input", () => {
  assert.throws(() => validateAppearanceEnvelope({ ...envelope("rain"), command: "open" }, approved), /fields/);
  assert.throws(() => validateAppearanceEnvelope(envelope("unknown"), approved), /skin/);
  const missing = envelope("rain");
  delete missing.settings.contrast;
  assert.throws(() => validateAppearanceEnvelope(missing, approved), /fields/);
  assert.throws(() => validateAppearanceEnvelope(envelope("rain", { fontSize: 15.5 }), approved), /fontSize/);
  assert.throws(() => validateAppearanceEnvelope(envelope("rain", { sidebarOpacity: 19 }), approved), /sidebarOpacity/);
  assert.throws(() => validateAppearanceEnvelope(envelope("rain", { font: "serif" }), approved), /font/);
  assert.throws(() => validateAppearanceEnvelope(envelope("rain", { textColor: "red" }), approved), /textColor/);
});

test("stores settings independently and materializes only the selected skin", async (context) => {
  const stateRoot = await fs.mkdtemp(path.join(os.tmpdir(), "dreamskin-appearance-"));
  context.after(() => fs.rm(stateRoot, { recursive: true, force: true }));
  const store = new AppearanceSettingsStore({ stateRoot, approvedSkinIds: approved });
  await store.put(envelope("rain", { sidebarOpacity: 20, font: "editorial" }));
  await store.put(envelope("sakura", { sidebarOpacity: 91, font: "rounded" }));
  assert.equal((await store.get("rain")).settings.sidebarOpacity, 20);
  assert.equal((await store.get("sakura")).settings.font, "rounded");
  await store.materialize("rain");
  const active = JSON.parse(await fs.readFile(path.join(stateRoot, "appearance.json"), "utf8"));
  assert.equal(active.sidebarOpacity, 0.2);
  assert.equal(active.font, "editorial");
  assert.equal((await fs.stat(path.join(stateRoot, "appearance-by-skin.json"))).mode & 0o777, 0o600);
});

test("serializes concurrent writes without losing another skin", async (context) => {
  const stateRoot = await fs.mkdtemp(path.join(os.tmpdir(), "dreamskin-appearance-concurrent-"));
  context.after(() => fs.rm(stateRoot, { recursive: true, force: true }));
  const store = new AppearanceSettingsStore({ stateRoot, approvedSkinIds: approved });
  await Promise.all([
    store.put(envelope("rain", { sidebarOpacity: 24 })),
    store.put(envelope("sakura", { sidebarOpacity: 93 })),
  ]);
  assert.equal((await store.get("rain")).settings.sidebarOpacity, 24);
  assert.equal((await store.get("sakura")).settings.sidebarOpacity, 93);
});

test("bridge saves settings for an exact allowed origin and rejects replay", async (context) => {
  const stateRoot = await fs.mkdtemp(path.join(os.tmpdir(), "dreamskin-bridge-"));
  context.after(() => fs.rm(stateRoot, { recursive: true, force: true }));
  const store = new AppearanceSettingsStore({ stateRoot, approvedSkinIds: approved });
  let callbackSkinId = null;
  const bridge = await createAppearanceBridge({
    port: 0,
    store,
    allowedOrigins: new Set(["https://nexotoken.net"]),
    onSettingsSaved: async ({ skinId }) => { callbackSkinId = skinId; },
  });
  context.after(() => bridge.close());
  const status = await request(bridge.server, "GET", "/v1/status", { origin: "https://nexotoken.net" });
  assert.deepEqual(status.body, { ok: true, protocolVersion: 1 });
  const challenge = await request(bridge.server, "GET", "/v1/challenge", { origin: "https://nexotoken.net" });
  const saved = await request(bridge.server, "POST", "/v1/settings", {
    origin: "https://nexotoken.net",
    challenge: challenge.body.challenge,
    body: envelope("rain"),
  });
  assert.equal(saved.status, 200);
  assert.equal(saved.body.skinId, "rain");
  assert.equal(callbackSkinId, "rain");
  const replay = await request(bridge.server, "POST", "/v1/settings", {
    origin: "https://nexotoken.net",
    challenge: challenge.body.challenge,
    body: envelope("rain"),
  });
  assert.equal(replay.status, 409);
  assert.equal(replay.body.error, "challenge_invalid");
});

test("bridge rejects unapproved origins and supports private-network preflight", async (context) => {
  const stateRoot = await fs.mkdtemp(path.join(os.tmpdir(), "dreamskin-bridge-origin-"));
  context.after(() => fs.rm(stateRoot, { recursive: true, force: true }));
  const store = new AppearanceSettingsStore({ stateRoot, approvedSkinIds: approved });
  const bridge = await createAppearanceBridge({ port: 0, store, allowedOrigins: new Set(["https://nexotoken.net"]) });
  context.after(() => bridge.close());
  const denied = await request(bridge.server, "GET", "/v1/challenge", { origin: "https://evil.example" });
  assert.equal(denied.status, 403);
  const preflight = await request(bridge.server, "OPTIONS", "/v1/settings", { origin: "https://nexotoken.net" });
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers["access-control-allow-origin"], "https://nexotoken.net");
  assert.equal(preflight.headers["access-control-allow-private-network"], "true");
});
