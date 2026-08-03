# Compact Skin Copy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Shorten home copy for every fixed skin and remove dots only from the identified blue-dress skin.

**Architecture:** The canonical renderer derives a bounded display title and exposes a validated theme ID. Canonical CSS hides inherited long copy globally and uses the ID attribute for one narrowly scoped decoration override; the existing sync tool generates identical platform assets.

**Tech Stack:** JavaScript renderer, CSS, Node.js test runner, shared runtime asset generator.

---

### Task 1: Lock the compact-copy contract

**Files:**
- Modify: `macos/tests/deep-skin-renderer-profile.test.mjs`
- Modify: `macos/tests/deep-skin-layout-css.test.mjs`

- [ ] Add assertions for a 12-character compact title, `data-dream-theme-id`, hidden inherited copy, and the exact single-skin CSS selector.
- [ ] Run both tests and confirm they fail on the missing behavior.

### Task 2: Implement the shared renderer and CSS behavior

**Files:**
- Modify: `runtime/renderer-inject.js`
- Modify: `runtime/dream-skin.css`
- Generate: `macos/assets/renderer-inject.js`
- Generate: `macos/assets/dream-skin.css`
- Generate: `windows/assets/renderer-inject.js`
- Generate: `windows/assets/dream-skin.css`

- [ ] Add `compactThemeName()` and set the validated theme ID on the document root.
- [ ] Hide the inherited long headline/tagline and render only the compact title.
- [ ] Disable particle/sidebar/card patterns only for `material-df6388daee46-e3486a16`.
- [ ] Run `node tools/sync-runtime-assets.mjs` and verify `--check` passes.

### Task 3: Verify and publish

**Files:**
- Modify: `macos/VERSION`, `windows/VERSION`, `macos/package.json`, `macos/scripts/common-macos.sh`, `macos/scripts/injector.mjs`, `windows/scripts/injector.mjs`
- Modify: `macos/CHANGELOG.md`, `windows/CHANGELOG.md`

- [ ] Run focused renderer/CSS tests and both payload checks.
- [ ] Bump all six version sources together and update both changelogs.
- [ ] Commit, fast-forward against `origin/main`, push, and verify the new CI/Release run.
