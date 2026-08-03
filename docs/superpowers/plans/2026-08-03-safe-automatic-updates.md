# Safe Automatic Updates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add safe, throttled, one-click automatic helper updates on macOS and Windows and route unknown canonical skin IDs into the updater.

**Architecture:** Keep release probing and artifact installation in small platform scripts, with native menu/tray code responsible only for scheduling and prompts. Verified updates replace only the helper; Windows defers installation while Codex is open.

**Tech Stack:** Swift/AppKit, Bash 3.2, PowerShell 5.1, GitHub Releases, Inno Setup, XCTest, Node test runner.

---

### Task 1: Lock the update contracts with failing tests

**Files:**
- Modify: `macos/menubar-app/Tests/DreamSkinCoreTests/CoreTests.swift`
- Modify: `macos/tests/installer-preflight.test.sh`
- Modify: `windows/tests/installer-static.tests.ps1`
- Modify: `windows/tests/community-theme-link.tests.ps1`

- [ ] Add assertions for a 24-hour startup throttle, updater packaging, exact versioned DMG/Setup names, SHA-256 validation, no automatic Codex termination, and unknown canonical skin links entering update handling.
- [ ] Run `swift test --package-path macos/menubar-app`, `bash macos/tests/installer-preflight.test.sh`, and the Windows suites where PowerShell is available; confirm the new assertions fail because the updater is not implemented.

### Task 2: Implement the macOS automatic updater

**Files:**
- Create: `macos/scripts/install-update-macos.sh`
- Modify: `macos/scripts/check-update-macos.sh`
- Modify: `macos/scripts/build-menubar-app.sh`
- Modify: `macos/menubar-app/Sources/DreamSkinCore/NexoSkinLink.swift`
- Modify: `macos/menubar-app/Sources/CodexDreamSkinMenuBar/AppDelegate.swift`

- [ ] Add pure URL classification for canonical-but-unknown fixed skin links and cover it in XCTest.
- [ ] Extend update JSON with normalized version and exact artifact names.
- [ ] Implement the detached installer: fixed HTTPS download, checksum verification, mounted app identity/version/architecture verification, transactional helper-only replacement with rollback, LaunchServices registration, and relaunch.
- [ ] Schedule a throttled startup check and reuse it for manual checks and old-client link handling.
- [ ] Run all macOS tests and build a universal app.

### Task 3: Implement the Windows automatic updater

**Files:**
- Modify: `windows/scripts/check-update.ps1`
- Modify: `windows/scripts/tray-dream-skin.ps1`
- Modify: `windows/scripts/theme-windows.ps1`
- Modify: `windows/installer/setup-bootstrap.ps1`

- [ ] Add `-Auto` and `-InstallPending` paths that download and verify exact Setup/SHA assets into a private update cache.
- [ ] Have tray startup perform the throttled check and a timer install only a verified pending Setup after Codex closes naturally.
- [ ] Route unknown canonical fixed skin IDs to the updater while preserving strict rejection of malformed/arbitrary links.
- [ ] Run the Windows static and link-contract suites.

### Task 4: Version, package, and locally repair the reported Mac

**Files:**
- Modify: `macos/VERSION`
- Modify: `windows/VERSION`
- Modify: `macos/package.json`
- Modify: `macos/scripts/common-macos.sh`
- Modify: `macos/scripts/injector.mjs`
- Modify: `windows/scripts/injector.mjs`
- Modify: `macos/CHANGELOG.md`
- Modify: `windows/CHANGELOG.md`

- [ ] Bump all six synchronized sources from `1.5.12` to `1.5.13` and document automatic updating.
- [ ] Run the full macOS test suite, portable syntax checks, artwork checks, and release build.
- [ ] Verify the app contains all 18 fixed skin IDs and both `arm64`/`x86_64` slices.
- [ ] Replace only `~/Applications/Codex Dream Skin.app`, re-register `dreamskin://`, relaunch the helper, and prove Codex PID is unchanged.
- [ ] Commit each completed task and attempt the normal main-branch release push; if repository permission blocks publication, retain the verified local release and report that exact external blocker without claiming public auto-update availability.

