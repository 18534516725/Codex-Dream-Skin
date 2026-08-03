# Codex Skin V2 visual QA

- Helper version: 1.6.7
- Host: macOS, Apple Silicon
- Logical platforms: macOS and Windows share the generated Theme V2 catalog and renderer assets
- Catalog: 18 approved themes, six visual families
- Source materials: 71 records, 69 unique candidates, two exact duplicates
- Video handling: one true dynamic candidate; 20 low-resolution sources use ambient reconstruction
- Review catalog: `themes/material-review-catalog.json` records all 69 candidate packages, their 4K/preview checksums and publication gate.

## Automated evidence

- Every approved poster is a decoded 3840×2400 WebP.
- Every approved gallery preview is a decoded 1200×750 WebP.
- Theme packages validate strict local poster/video names and reject arbitrary URLs.
- Dynamic media is muted, looping, inert, pauses while hidden or reduced-motion is active, and falls back to its poster on playback failure.
- Full UI tests cover sidebar root, section labels, rows, hover/selected states, scrollbar, account footer, top bar, composer, modal and new-window state.
- All 18 themes produce distinct family/sidebar/composer/accent profiles.
- macOS `DreamSkinCore` builds with the generated catalog resource.
- Windows logical catalog and payload tests pass locally; PowerShell runtime and installer execution remains delegated to Windows CI because PowerShell is unavailable on this Mac.

## Environment limitations

- The complete Swift XCTest bundle is unavailable in this local toolchain (`XCTest` module missing), while the production `DreamSkinCore` target compiles successfully.
- The full live doctor check sees the currently installed older helper payload at the active Codex debugging port. No forced Codex restart was used to hide that environmental mismatch.
- Copyright-review candidates remain under ignored `.artifacts/` storage and are not published in the public catalog.
- All candidate media remains admin-review-only until originality or redistribution rights are confirmed; metadata submission does not make the source assets downloadable.
