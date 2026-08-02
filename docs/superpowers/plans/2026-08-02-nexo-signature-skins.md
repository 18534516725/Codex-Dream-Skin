# Nexo Signature Skins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade all 12 fixed Nexo skins into high-resolution, full-interface Codex themes with distinct sidebar, home, composer, selection and accent treatments on macOS and Windows.

**Architecture:** Extend the existing fixed-skin contract with a compact visual profile and serialize it into the existing theme JSON consumed by the shared CSS injector. Keep one canonical CSS implementation mirrored byte-for-byte across runtime, macOS and Windows, while platform adapters only provide the profile. Replace the 12 website originals with composition-preserving 3840×2400 WebP masters so the existing HTTPS asset URLs remain stable.

**Tech Stack:** Swift/AppKit, PowerShell 5.1+, Node.js 20, CSS custom properties, WebP, Codex Dream Skin Studio CDP verifier, React/Vite static assets.

---

### Task 1: Lock the visual-profile contract with failing tests

**Files:**
- Modify: `macos/menubar-app/Tests/DreamSkinCoreTests/CoreTests.swift`
- Modify: `windows/tests/community-theme-link.tests.ps1`
- Modify: `macos/tests/nexo-vivid-profile.test.mjs`
- Modify: `windows/tests/nexo-vivid-profile.test.mjs`

- [ ] **Step 1: Add macOS assertions for every fixed skin profile**

Assert that each entry exposes non-empty `accentRGB`, `secondaryRGB`, `panelRGB`, `signature`, valid unit `focusX/focusY`, and `glowStrength` in `0...1`, while preserving `appearance == "dark"` and `taskMode == "full"`.

- [ ] **Step 2: Add equivalent Windows assertions**

Assert the PowerShell resolver returns the same fields and that `Invoke-DreamSkinNexoApply` forwards them into `Set-DreamSkinActiveTheme`.

- [ ] **Step 3: Run tests and record the expected failure**

Run:

```bash
node macos/tests/nexo-vivid-profile.test.mjs
node windows/tests/nexo-vivid-profile.test.mjs
```

Expected: both fail because the new profile fields are absent.

- [ ] **Step 4: Commit the failing tests**

```bash
git add macos/menubar-app/Tests/DreamSkinCoreTests/CoreTests.swift macos/tests/nexo-vivid-profile.test.mjs windows/tests/community-theme-link.tests.ps1 windows/tests/nexo-vivid-profile.test.mjs
git commit -m "test: define fixed skin signature profiles"
```

### Task 2: Implement all 12 macOS and Windows visual profiles

**Files:**
- Modify: `macos/menubar-app/Sources/DreamSkinCore/NexoSkinLink.swift`
- Modify: `macos/menubar-app/Sources/CodexDreamSkinMenuBar/AppDelegate.swift`
- Modify: `windows/scripts/theme-windows.ps1`
- Modify: `windows/scripts/apply-community-theme.ps1`
- Modify: `macos/scripts/write-theme.mjs`
- Modify: `windows/scripts/theme-core.ps1`

- [ ] **Step 1: Extend the profile type**

Add strongly named fields for `accentRGB`, `secondaryRGB`, `panelRGB`, `glowStrength`, `signature`, `focusX`, and `focusY`. Give every catalog entry an intentional palette sampled from its artwork rather than a shared purple fallback.

- [ ] **Step 2: Serialize the fields into theme JSON**

Write the profile under `visual` and keep `art.focusX`, `art.focusY`, `art.safeArea`, and `art.taskMode` in the current schema. Validate RGB triplets, unit coordinates, signature length and glow range before writing.

- [ ] **Step 3: Pass the complete profile from both platform adapters**

macOS adds writer arguments for the visual fields; Windows builds the equivalent `visual` object before calling `Set-DreamSkinActiveTheme`.

- [ ] **Step 4: Run the contract tests**

Run:

```bash
node macos/tests/nexo-vivid-profile.test.mjs
node windows/tests/nexo-vivid-profile.test.mjs
bash -n macos/scripts/load-image-theme-macos.sh
node --check macos/scripts/write-theme.mjs
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit the profile implementation**

```bash
git add macos/menubar-app/Sources macos/scripts windows/scripts
git commit -m "feat: add signature profiles for fixed skins"
```

### Task 3: Add full-interface signature styling

**Files:**
- Modify: `runtime/dream-skin.css`
- Modify: `macos/assets/dream-skin.css`
- Modify: `windows/assets/dream-skin.css`
- Modify: `runtime/renderer-inject.js`
- Modify: `macos/assets/renderer-inject.js`
- Modify: `windows/assets/renderer-inject.js`
- Modify: `macos/tests/native-immersive-css.test.mjs`
- Create: `macos/tests/signature-skin-css.test.mjs`

- [ ] **Step 1: Add a failing CSS contract test**

Require profile-backed CSS variables, a continuous home background, theme-tinted sidebar and resize chrome, selected-project accent, refined composer surface, home-title detail, non-interactive signature decoration, focus-visible treatment and `prefers-reduced-motion` handling. Also require the three platform CSS files and renderer files to remain identical.

- [ ] **Step 2: Run the test and confirm it fails**

```bash
node macos/tests/signature-skin-css.test.mjs
```

Expected: FAIL because signature selectors and variables do not exist.

- [ ] **Step 3: Inject validated visual variables**

Map the theme JSON profile to `--ds-accent-rgb`, `--ds-secondary-rgb`, `--ds-panel-rgb`, `--ds-glow-strength` and an escaped signature attribute. Remove all injected attributes during restore or theme replacement.

- [ ] **Step 4: Implement the shared refined surfaces**

Use layered translucent color, one-pixel theme borders, inset highlights and low-radius environmental glow. Keep decoration non-interactive. Reduce the home veil so the art remains visible; keep the task veil stronger for reading.

- [ ] **Step 5: Mirror canonical assets and run tests**

```bash
cmp runtime/dream-skin.css macos/assets/dream-skin.css
cmp runtime/dream-skin.css windows/assets/dream-skin.css
cmp runtime/renderer-inject.js macos/assets/renderer-inject.js
cmp runtime/renderer-inject.js windows/assets/renderer-inject.js
node macos/tests/native-immersive-css.test.mjs
node macos/tests/signature-skin-css.test.mjs
```

Expected: all commands exit 0.

- [ ] **Step 6: Commit the interface styling**

```bash
git add runtime macos/assets windows/assets macos/tests
git commit -m "feat: style the complete Codex shell per skin"
```

### Task 4: Produce and validate 12 high-resolution background masters

**Files:**
- Modify: `/Users/wangqi/work/payment-platform/frontend/public/codex-skins/originals/01-stellar-voyager.webp`
- Modify: `/Users/wangqi/work/payment-platform/frontend/public/codex-skins/originals/02-sakura-signal.webp`
- Modify: `/Users/wangqi/work/payment-platform/frontend/public/codex-skins/originals/03-neon-courier.webp`
- Modify: `/Users/wangqi/work/payment-platform/frontend/public/codex-skins/originals/04-mist-beacon.webp`
- Modify: `/Users/wangqi/work/payment-platform/frontend/public/codex-skins/originals/05-rain-harbor.webp`
- Modify: `/Users/wangqi/work/payment-platform/frontend/public/codex-skins/originals/06-crimson-forge.webp`
- Modify: `/Users/wangqi/work/payment-platform/frontend/public/codex-skins/originals/07-cloud-antler.webp`
- Modify: `/Users/wangqi/work/payment-platform/frontend/public/codex-skins/originals/08-midnight-terminal.webp`
- Modify: `/Users/wangqi/work/payment-platform/frontend/public/codex-skins/originals/09-retro-orbit.webp`
- Modify: `/Users/wangqi/work/payment-platform/frontend/public/codex-skins/originals/10-strategy-atrium.webp`
- Modify: `/Users/wangqi/work/payment-platform/frontend/public/codex-skins/originals/11-aurora-leviathan.webp`
- Modify: `/Users/wangqi/work/payment-platform/frontend/public/codex-skins/originals/12-ink-ridge-guardian.webp`
- Create: `/Users/wangqi/work/payment-platform/frontend/scripts/validate-codex-skin-assets.mjs`
- Modify: `/Users/wangqi/work/payment-platform/frontend/package.json`

- [ ] **Step 1: Add an asset validation command**

Validate exactly 12 expected filenames, WebP decoding, width at least 3840, height at least 2160, aspect ratio between 1.55 and 1.75, and a reasonable per-file size ceiling. Add the command to the frontend test scripts without introducing a new dependency when native image metadata tools are sufficient.

- [ ] **Step 2: Run validation and confirm all old images fail resolution**

```bash
cd /Users/wangqi/work/payment-platform/frontend
pnpm run test:codex-skins
```

Expected: FAIL listing all 12 files at approximately 1586×992.

- [ ] **Step 3: Enhance each original with the image editing workflow**

For each source, preserve its character, scene, palette and composition; reconstruct fine detail at a 16:10 master size; prohibit UI, lettering, logos and new foreground objects. Visually inspect every generated master before replacing the website file.

- [ ] **Step 4: Convert approved masters to high-quality WebP**

Use 3840×2400 output, retain color profile, and choose a quality setting that avoids banding in gradients while keeping download size practical.

- [ ] **Step 5: Run asset and frontend verification**

```bash
cd /Users/wangqi/work/payment-platform/frontend
pnpm run test:codex-skins
pnpm run build
git diff --check
```

Expected: asset test and production build exit 0.

- [ ] **Step 6: Commit only the skin assets and validator**

```bash
git add frontend/public/codex-skins/originals frontend/scripts/validate-codex-skin-assets.mjs frontend/package.json
git commit -m "feat: upgrade Codex skins to high resolution"
```

### Task 5: Build, install and hot-verify the macOS helper

**Files:**
- Build output: `/Users/wangqi/Library/Caches/NexoCodexDreamSkin/Codex Dream Skin-signature.app`
- Install target: `/Users/wangqi/Applications/Codex Dream Skin.app`

- [ ] **Step 1: Build the universal helper**

```bash
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
DREAMSKIN_SDK="$sdk_path" macos/scripts/build-menubar-app.sh --skip-tests --output "/Users/wangqi/Library/Caches/NexoCodexDreamSkin/Codex Dream Skin-signature.app"
```

Expected: the executable reports both `x86_64` and `arm64` architectures.

- [ ] **Step 2: Install the helper without restarting Codex**

Replace only the user-installed helper after preserving its previous bundle in the cache. Do not close or restart Codex.

- [ ] **Step 3: Hot-apply Sakura and verify the real UI**

Apply `sakura-signal`, capture the home route and a task route, and run `verify-dream-skin-macos.sh`. Expected: `pass: true`, visible sidebar/composer, no overflow, clearly visible wallpaper, Sakura-tinted sidebar and composer.

- [ ] **Step 4: Switch to two contrasting themes**

Hot-apply `midnight-terminal` and `cloud-antler`; verify their accent variables and screenshots differ from Sakura and no previous signature remains.

- [ ] **Step 5: Commit any verification fixes**

```bash
git add runtime macos windows
git commit -m "fix: polish signature skin verification"
```

Only create this commit if verification required source changes.

### Task 6: Release the admin-only test update

**Files:**
- Repository: `/Users/wangqi/work/payment-platform`
- Helper repository: `/Users/wangqi/Library/Caches/NexoCodexDreamSkin/source-1c7a859ed51bcfe4923f6483a5625a6e63f97657`

- [ ] **Step 1: Verify repository cleanliness and commit ancestry**

Run `git status --short`, `git diff --check`, relevant tests, and confirm both repositories contain only intended changes. Preserve unrelated user files.

- [ ] **Step 2: Publish only through Git**

Push `main` without force. If the helper repository still rejects the authenticated account, stop and report the exact permission blocker; do not upload code around Git.

- [ ] **Step 3: Deploy only the affected platform frontend**

Follow the repository production sequence: local test and commit, push `origin/main`, production clean-worktree check, `git pull --ff-only`, build `frontend`, update only the frontend container, then verify homepage and high-resolution asset HTTP responses.

- [ ] **Step 4: Confirm admin-only visibility**

Verify an administrator can see and apply the skins while a normal user cannot see the menu entry and is redirected away from the skin view.

- [ ] **Step 5: Report evidence and remaining distribution limits**

Report commit SHAs, updated service, macOS screenshots, asset dimensions, Windows test coverage, unchanged services and any helper-release permission issue.
