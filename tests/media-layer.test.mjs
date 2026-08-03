import assert from "node:assert/strict";
import { createRequire } from "node:module";
import test from "node:test";

const require = createRequire(import.meta.url);
const createDreamSkinMediaLayer = require("../runtime/media-layer.js");

class FakeElement {
  constructor(tagName) {
    this.tagName = tagName.toUpperCase();
    this.children = [];
    this.listeners = new Map();
    this.style = {};
    this.attributes = new Map();
    this.parentNode = null;
    this.paused = true;
    this.playCalls = 0;
    this.pauseCalls = 0;
  }

  appendChild(node) {
    node.parentNode = this;
    this.children.push(node);
    return node;
  }

  remove() {
    if (!this.parentNode) return;
    this.parentNode.children = this.parentNode.children.filter((child) => child !== this);
    this.parentNode = null;
  }

  setAttribute(name, value) { this.attributes.set(name, String(value)); }
  addEventListener(name, handler) { this.listeners.set(name, handler); }
  removeEventListener(name) { this.listeners.delete(name); }
  dispatch(name) { this.listeners.get(name)?.({ type: name }); }
  async play() { this.playCalls += 1; this.paused = false; }
  pause() { this.pauseCalls += 1; this.paused = true; }
}

function environment({ reducedMotion = false } = {}) {
  const documentListeners = new Map();
  const mediaListeners = new Map();
  const body = new FakeElement("body");
  const mediaQuery = {
    matches: reducedMotion,
    addEventListener: (name, handler) => mediaListeners.set(name, handler),
    removeEventListener: (name) => mediaListeners.delete(name),
    setMatches(value) {
      this.matches = value;
      mediaListeners.get("change")?.({ matches: value });
    },
  };
  const document = {
    body,
    hidden: false,
    createElement: (tag) => new FakeElement(tag),
    addEventListener: (name, handler) => documentListeners.set(name, handler),
    removeEventListener: (name) => documentListeners.delete(name),
    setHidden(value) {
      this.hidden = value;
      documentListeners.get("visibilitychange")?.({ type: "visibilitychange" });
    },
  };
  return { document, matchMedia: () => mediaQuery, mediaQuery };
}

test("poster-only media layer is inert and disposable", () => {
  const env = environment();
  const controller = createDreamSkinMediaLayer(env);
  const layer = controller.mount({ posterUrl: "blob:poster", videoUrl: null });
  assert.equal(layer.root.style.pointerEvents, "none");
  assert.match(layer.root.style.backgroundImage, /blob:poster/);
  assert.equal(layer.video, null);
  assert.equal(env.document.body.children.length, 1);
  layer.dispose();
  assert.equal(env.document.body.children.length, 0);
});

test("video layer is muted, looping, non-interactive and pauses while hidden", async () => {
  const env = environment();
  const layer = createDreamSkinMediaLayer(env).mount({
    posterUrl: "blob:poster",
    videoUrl: "blob:video",
  });
  await Promise.resolve();
  assert.equal(layer.video.muted, true);
  assert.equal(layer.video.loop, true);
  assert.equal(layer.video.controls, false);
  assert.equal(layer.video.playsInline, true);
  assert.equal(layer.video.style.pointerEvents, "none");
  assert.equal(layer.video.playCalls, 1);
  env.document.setHidden(true);
  assert.equal(layer.video.paused, true);
  env.document.setHidden(false);
  await Promise.resolve();
  assert.equal(layer.video.playCalls, 2);
  layer.dispose();
});

test("reduced motion and video errors retain the poster fallback", async () => {
  const env = environment({ reducedMotion: true });
  const layer = createDreamSkinMediaLayer(env).mount({
    posterUrl: "blob:poster",
    videoUrl: "blob:video",
  });
  await Promise.resolve();
  assert.equal(layer.video.playCalls, 0);
  assert.equal(layer.video.style.display, "none");
  env.mediaQuery.setMatches(false);
  await Promise.resolve();
  assert.equal(layer.video.playCalls, 1);
  layer.video.dispatch("error");
  assert.equal(layer.video.style.display, "none");
  assert.match(layer.root.style.backgroundImage, /blob:poster/);
  layer.dispose();
});
