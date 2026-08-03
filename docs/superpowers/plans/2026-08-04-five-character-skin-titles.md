# Five-character Skin Titles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render one clean skin title of at most five characters at every window width.

**Architecture:** The shared renderer owns title normalization and the exact approved-skin alias. Shared CSS permanently hides the native marketplace headline and sizes only the generated title; synchronized platform assets consume the same sources.

**Tech Stack:** JavaScript, CSS, Node.js test runner, macOS shell/Swift packaging, Windows PowerShell packaging.

---

### Task 1: Lock the failed narrow-window behavior

**Files:**
- Modify: `macos/tests/deep-skin-renderer-profile.test.mjs`
- Modify: `macos/tests/deep-skin-layout-css.test.mjs`

- [ ] Add assertions for `深蓝礼服`, `slice(0, 5)`, and no `18px` native headline override.
- [ ] Run `node --test macos/tests/deep-skin-renderer-profile.test.mjs macos/tests/deep-skin-layout-css.test.mjs` and confirm the new assertions fail.

### Task 2: Implement the minimal shared fix

**Files:**
- Modify: `runtime/renderer-inject.js`
- Modify: `runtime/dream-skin.css`
- Generate: `macos/assets/renderer-inject.js`
- Generate: `windows/assets/renderer-inject.js`
- Generate: `macos/assets/dream-skin.css`
- Generate: `windows/assets/dream-skin.css`

- [ ] Add the exact approved-skin alias and reduce the generic Unicode cap to five.
- [ ] Keep the narrow native headline at `font-size: 0` and set only `::before` to a responsive title size.
- [ ] Run `node tools/sync-runtime-assets.mjs` followed by `node tools/sync-runtime-assets.mjs --check`.
- [ ] Re-run the focused tests and confirm they pass.

### Task 3: Verify and publish an immutable client release

**Files:**
- Modify: `macos/VERSION`
- Modify: `windows/VERSION`
- Modify: `macos/package.json`
- Modify: `macos/scripts/common-macos.sh`
- Modify: `macos/scripts/injector.mjs`
- Modify: `windows/scripts/injector.mjs`
- Modify: `macos/CHANGELOG.md`
- Modify: `windows/CHANGELOG.md`

- [ ] Bump all six version sources together and document the correction.
- [ ] Run both portable Node suites, payload validation, runtime synchronization and `git diff --check`.
- [ ] Commit, push `main`, wait for CI and Release success, then verify DMG, Setup.exe and `SHA256SUMS.txt` on the public release.
