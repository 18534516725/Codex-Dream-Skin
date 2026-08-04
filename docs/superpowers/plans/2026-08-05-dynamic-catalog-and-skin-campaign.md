# Dynamic Catalog and Skin Campaign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the released helper securely apply future platform-approved skins without a client rebuild, verify the complete one-click user flow, and locally add a homepage recharge-skin campaign while removing the old floating campaign notice.

**Architecture:** The platform signs a strict version-2 catalog that includes immutable asset hashes plus a bounded full-interface visual profile. The macOS and Windows helpers pin the platform Ed25519 public key, verify the signed catalog and resolve new IDs from it while retaining the embedded catalog as an offline last-known-good fallback. The website continues to create user-specific apply intents and only emits `dreamskin://apply?skin=<approved-id>`; homepage promotion uses the existing carousel navigation and the platform remains local-only in this task.

**Tech Stack:** Node.js 20, Express/Jest, React 19/TypeScript/Vite, Swift/CryptoKit, PowerShell 5.1/7, GitHub Actions.

---

### Task 1: Lock the signed visual-profile contract

**Files:**
- Modify: `runtime/signed-nexo-catalog.mjs`
- Modify: `macos/menubar-app/Sources/DreamSkinCore/SignedNexoCatalog.swift`
- Modify: `windows/scripts/signed-nexo-catalog.ps1`
- Test: `tests/signed-nexo-catalog.test.mjs`
- Test: `macos/menubar-app/Tests/DreamSkinCoreTests/CoreTests.swift`
- Test: `windows/tests/signed-nexo-catalog.tests.ps1`

- [ ] Add failing schema-v2 tests requiring `taskMode` and an exact, bounded `visual` object on every signed skin.
- [ ] Implement identical validation on Node, Swift and PowerShell, retaining schema-v1 verification only for cached backward compatibility.
- [ ] Resolve macOS and Windows theme entries from the signed profile rather than generic colors.
- [ ] Run the focused Node, Swift and PowerShell-compatible contract suites.

### Task 2: Pin the production catalog key and enable remote additions

**Files:**
- Modify: `macos/menubar-app/Sources/DreamSkinCore/NexoSkinLink.swift`
- Modify: `windows/scripts/signed-nexo-catalog.ps1`
- Modify: `macos/scripts/injector.mjs`
- Modify: `windows/scripts/injector.mjs`
- Test: `macos/tests/appearance-settings.test.mjs`
- Test: `windows/tests/appearance-settings.test.mjs`

- [ ] Generate one Ed25519 keypair locally without printing or committing the private key; store only the raw/SPKI public forms in the helper.
- [ ] Add tests that the production key ID is pinned and malformed or unsigned catalogs remain fail-closed.
- [ ] Build the appearance-settings allowlist from the verified fresh/LKG catalog in addition to the embedded catalog, so settings for a newly approved ID apply after installation.
- [ ] Verify both platform injectors reject arbitrary IDs and accept a signed remote-only fixture.

### Task 3: Emit complete signed themes from the platform

**Files:**
- Modify: `/Users/wangqi/work/payment-platform/backend/src/services/codexSkins/CodexSkinCatalogSigner.js`
- Modify: `/Users/wangqi/work/payment-platform/backend/src/services/codexSkins/CodexSkinCatalogService.js`
- Modify: `/Users/wangqi/work/payment-platform/backend/tests/unit/services/CodexSkinCatalogService.test.js`

- [ ] Add a failing backend test for schema version 2 and exact visual-profile fields.
- [ ] Derive the bounded visual profile from existing `appearance`, `focus_x`, `focus_y` and `visual_template` fields; do not require a database write or migration in this task.
- [ ] Sign and return schema version 2 while preserving fixed origin, hashes, expiry and revocations.
- [ ] Run backend catalog, entitlement, device verification and error-sanitization tests.

### Task 4: Repair and exercise the one-click user workflow

**Files:**
- Modify: `/Users/wangqi/work/payment-platform/frontend/src/pages/CodexSkins/CodexSkins.tsx`
- Modify: `/Users/wangqi/work/payment-platform/frontend/src/pages/CodexSkins/skinCatalog.ts`
- Modify: `/Users/wangqi/work/payment-platform/frontend/src/pages/CodexSkins/skinAppearanceStorage.ts`
- Test: `/Users/wangqi/work/payment-platform/frontend/src/pages/CodexSkins/*.test.ts`

- [ ] Add tests for logged-out navigation, unlocked user apply, admin bypass, remote-only IDs, helper launch grace period, appearance sync and safe failure copy.
- [ ] Register verified remote catalog IDs at runtime so full preview settings and strict deep links support new skins without loosening the ID format.
- [ ] Keep the install prompt manual and only show it after the helper remains unreachable through the full launch window.
- [ ] Run focused frontend tests and production build.

### Task 5: Add the local homepage skin campaign

**Files:**
- Modify: `/Users/wangqi/work/payment-platform/frontend/src/components/LandingFeatureCarousel/LandingFeatureCarousel.tsx`
- Modify: `/Users/wangqi/work/payment-platform/frontend/src/components/LandingFeatureCarousel/LandingFeatureCarousel.css`
- Modify: `/Users/wangqi/work/payment-platform/frontend/src/i18n/locales/zh/landing.json`
- Modify: `/Users/wangqi/work/payment-platform/frontend/src/i18n/locales/en/landing.json`
- Test: `/Users/wangqi/work/payment-platform/frontend/src/components/LandingFeatureCarousel/skinCampaign.test.ts`

- [ ] Add a failing source contract asserting a dedicated `codex-skins` slide and no floating `CreatorCampaignNotice` rendering.
- [ ] Add a refined editorial skin-passport visual, concise recharge reward copy and direct carousel CTA through the existing authenticated navigation.
- [ ] Remove the bottom-right old campaign notice while preserving its carousel campaign/dialog.
- [ ] Verify responsive, keyboard, reduced-motion, light and dark behavior in the existing carousel styles.

### Task 6: Regression, package and helper-only release

**Files:**
- Modify: the six helper version sources required by `AGENTS.md`
- Modify: `CHANGELOG.md`, `macos/CHANGELOG.md`, `windows/CHANGELOG.md`
- Modify: `TASK_PROGRESS.md`

- [ ] Run runtime sync, portable Node suites, complete applicable macOS suite, Windows source/static regressions, version consistency, package payload checks and `git diff --check`.
- [ ] Run platform backend focused tests, frontend focused tests and production build without deploying or committing the platform repository.
- [ ] Bump the helper to v1.6.28, commit only the helper repository, fast-forward push `main`, and monitor CI/Release without opening a browser.
- [ ] Verify the public Release contains non-empty DMG, Setup.exe and `SHA256SUMS.txt`; record any platform-only local changes separately.
