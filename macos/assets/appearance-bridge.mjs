import http from "node:http";
import { randomBytes, timingSafeEqual } from "node:crypto";

export const APPEARANCE_BRIDGE_PROTOCOL_VERSION = 2;
export const APPEARANCE_BRIDGE_PORT = 17384;
const MAX_BODY_BYTES = 16 * 1024;
const CHALLENGE_TTL_MS = 30_000;

function json(response, status, value) {
  const body = JSON.stringify(value);
  response.writeHead(status, {
    "Content-Type": "application/json; charset=utf-8",
    "Content-Length": Buffer.byteLength(body),
    "Cache-Control": "no-store",
    "X-Content-Type-Options": "nosniff",
  });
  response.end(body);
}

function sameToken(left, right) {
  if (typeof left !== "string" || typeof right !== "string") return false;
  const a = Buffer.from(left);
  const b = Buffer.from(right);
  return a.length === b.length && timingSafeEqual(a, b);
}

async function readJson(request) {
  if (!String(request.headers["content-type"] || "").toLowerCase().startsWith("application/json")) {
    throw Object.assign(new Error("content_type_invalid"), { status: 415 });
  }
  const chunks = [];
  let total = 0;
  for await (const chunk of request) {
    total += chunk.length;
    if (total > MAX_BODY_BYTES) throw Object.assign(new Error("request_too_large"), { status: 413 });
    chunks.push(chunk);
  }
  try {
    return JSON.parse(Buffer.concat(chunks).toString("utf8"));
  } catch {
    throw Object.assign(new Error("json_invalid"), { status: 400 });
  }
}

export async function createAppearanceBridge({
  port = APPEARANCE_BRIDGE_PORT,
  store,
  allowedOrigins,
  getActiveSkinId = () => null,
  onSettingsSaved = async () => {},
  now = () => Date.now(),
}) {
  if (!store || !(allowedOrigins instanceof Set) || allowedOrigins.size < 1 || typeof getActiveSkinId !== "function") {
    throw new Error("Appearance bridge configuration is invalid");
  }
  const challenges = new Map();
  const server = http.createServer(async (request, response) => {
    response.setHeader("Cache-Control", "no-store");
    const origin = request.headers.origin;
    if (typeof origin !== "string" || !allowedOrigins.has(origin)) {
      return json(response, 403, { ok: false, error: "origin_denied" });
    }
    response.setHeader("Access-Control-Allow-Origin", origin);
    response.setHeader("Vary", "Origin");
    const url = new URL(request.url || "/", "http://127.0.0.1");

    if (request.method === "OPTIONS" && url.pathname === "/v1/settings") {
      response.writeHead(204, {
        "Access-Control-Allow-Methods": "POST, OPTIONS",
        "Access-Control-Allow-Headers": "content-type, x-dreamskin-challenge",
        "Access-Control-Allow-Private-Network": "true",
        "Access-Control-Max-Age": "300",
      });
      return response.end();
    }
    if (request.method === "GET" && url.pathname === "/v1/status") {
      const activeSkinId = await getActiveSkinId();
      return json(response, 200, {
        ok: true,
        protocolVersion: APPEARANCE_BRIDGE_PROTOCOL_VERSION,
        activeSkinId: typeof activeSkinId === "string" ? activeSkinId : null,
      });
    }
    if (request.method === "GET" && url.pathname === "/v1/challenge") {
      const challenge = randomBytes(32).toString("base64url");
      challenges.set(challenge, now() + CHALLENGE_TTL_MS);
      return json(response, 200, {
        ok: true,
        protocolVersion: APPEARANCE_BRIDGE_PROTOCOL_VERSION,
        challenge,
        expiresInMs: CHALLENGE_TTL_MS,
      });
    }
    if (request.method === "POST" && url.pathname === "/v1/settings") {
      const supplied = request.headers["x-dreamskin-challenge"];
      let matched = null;
      for (const [candidate, expiresAt] of challenges) {
        if (expiresAt <= now()) challenges.delete(candidate);
        else if (sameToken(supplied, candidate)) matched = candidate;
      }
      if (!matched) return json(response, 409, { ok: false, error: "challenge_invalid" });
      challenges.delete(matched);
      try {
        const saved = await store.put(await readJson(request));
        await onSettingsSaved(saved);
        return json(response, 200, {
          ok: true,
          protocolVersion: APPEARANCE_BRIDGE_PROTOCOL_VERSION,
          skinId: saved.skinId,
        });
      } catch (error) {
        const status = Number.isInteger(error?.status) ? error.status : 422;
        const stable = status === 413 ? "request_too_large" : status === 415 ? "content_type_invalid" :
          status === 400 ? "json_invalid" : "settings_invalid";
        return json(response, status, { ok: false, error: stable });
      }
    }
    return json(response, 404, { ok: false, error: "not_found" });
  });
  server.requestTimeout = 2_000;
  server.headersTimeout = 2_000;
  server.keepAliveTimeout = 1_000;
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(port, "127.0.0.1", () => {
      server.off("error", reject);
      resolve();
    });
  });
  return {
    server,
    close: () => new Promise((resolve) => server.close(() => resolve())),
  };
}
