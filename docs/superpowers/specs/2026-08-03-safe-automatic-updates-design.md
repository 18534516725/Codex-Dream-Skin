# Safe Automatic Updates Design

## Goal

Prevent old Codex Dream Skin clients from rejecting newly published Nexo skin IDs. macOS and Windows clients automatically check for a newer release, offer one-click updating, validate the official release artifact, preserve user themes, and never restart Codex as part of the helper update.

## User experience

- Check once shortly after helper startup and then at most once every 24 hours.
- Network failures during background checks are silent and never block existing themes.
- A newer version produces one native prompt with **Update now** and **Later**.
- Selecting **Update now** downloads the platform installer from the fixed GitHub repository, verifies its companion SHA-256, then updates the helper.
- macOS exits and replaces only the menu-bar helper, relaunching it after installation. Codex stays running.
- Windows stages the verified Setup executable. If Codex is open, installation waits until Codex closes naturally; it never closes or restarts Codex for an automatic update.
- A canonical `dreamskin://apply?skin=...` link with an unknown fixed ID is treated as a likely old-client signal and enters the update check instead of immediately reporting an invalid URL.

## Security boundary

- Release metadata comes only from `api.github.com/repos/18534516725/Codex-Dream-Skin/releases/latest` over TLS.
- Artifacts use exact versioned names and the fixed release download path.
- The companion checksum filename, digest syntax, downloaded byte count, bundle/application identity, embedded engine version, and platform architecture are validated.
- Redirects are limited to HTTPS GitHub release infrastructure.
- User themes and images remain outside the application bundle and are not moved or deleted.
- Invalid metadata, invalid checksums, unexpected app identity, downgrade attempts, and incomplete downloads fail closed.

## Components

- macOS `check-update-macos.sh` remains the bounded release metadata probe and gains machine-readable artifact data.
- macOS `install-update-macos.sh` owns download, verification, transactional replacement, rollback, and helper relaunch.
- `AppDelegate` owns scheduling, native prompts, pending-link retry intent, and launching the detached installer.
- Windows `check-update.ps1` owns scheduled probing, verified Setup staging, pending-update state, and launching Setup only after Codex is closed.
- Windows tray startup triggers the bounded background check and periodically attempts an already-verified pending install.

## Verification

- Unit/static tests cover semantic versions, 24-hour throttling, exact asset names, checksum validation contracts, unknown fixed-link routing, no Codex termination, and packaging of updater scripts.
- macOS Swift and shell test suites must pass; Windows PowerShell/static tests must pass on CI/PowerShell-capable runners.
- A local macOS release app must be built, inspected for both architectures and all 18 IDs, installed over v1.5.12, and registered as the `dreamskin://` handler without restarting Codex.

