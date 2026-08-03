# Nexo Codex Skin

<p align="center">
  <a href="./README.md">中文</a> · <strong>English</strong>
</p>

<p align="center">
  <strong>A cross-platform immersive Codex skin helper by NexoToken</strong><br>
  Native UI preserved · Full-window themes · macOS / Windows · Safe automatic updates
</p>

<p align="center">
  <a href="https://nexotoken.net"><strong>Open NexoToken</strong></a> ·
  <a href="https://github.com/18534516725/Codex-Dream-Skin/releases"><strong>Download the helper</strong></a>
</p>

> This repository contains the client engine for NexoToken's skin system. It is not a public theme-download site. Installers contain the rendering engine only; NexoToken premium artwork and theme packs are not bundled. Theme discovery, eligibility, and one-click apply entry points are controlled by the NexoToken platform.

## How to use it

1. Sign in at [NexoToken](https://nexotoken.net) and open the Codex skins page made available to your account.
2. On first use, install the helper for your operating system from [GitHub Releases](https://github.com/18534516725/Codex-Dream-Skin/releases).
3. Return to NexoToken, choose an eligible skin, and select **Apply**.
4. The helper validates the fixed theme identifier, asset origin, and image integrity, then applies the skin and verifies the real Codex window.

The skin feature is currently in an administrator-only preview. Eligibility and top-up reward rules will be shown by NexoToken when general access opens.

## Install

| Platform | Package | Graphical guide |
|---|---|---|
| macOS (Apple Silicon / Intel) | `CodexDreamSkin-vX.Y.Z.dmg` | [macOS installation](./docs/install-macos.md) |
| Windows 10 / 11 | `CodexDreamSkin-Setup-vX.Y.Z.exe` | [Windows installation](./docs/install-windows.md) |

Users do not need to clone this repository, install Node.js, or run `.sh` / `.ps1` files manually. The installed helper periodically checks formal releases from this repository. Updates are accepted only after version, application identity, and SHA-256 verification, and are scheduled to avoid interrupting an active Codex session whenever possible.

## Capabilities

- **Complete theming** — background, sidebar, title area, composer, selection states, dialogs, and new windows follow one visual system.
- **Native interaction** — no fake UI screenshot is placed over Codex; existing controls remain usable.
- **Cross-platform parity** — macOS and Windows share the Theme V2 contract and generated catalog.
- **High-resolution and motion** — supports 4K static artwork and bounded dynamic media with safe fallbacks.
- **Constrained apply links** — accepts fixed theme identifiers, never arbitrary URLs, file paths, or commands.
- **Verified recovery** — success requires visible renderer verification; failures preserve a route back to the stock appearance.
- **Automatic updates** — an older helper can update before handling a newer theme contract.

## Distribution boundary

- Client menus do not link to external galleries, online studios, or third-party theme sites.
- Public GitHub Releases distribute the macOS and Windows helper, not NexoToken's premium skin collection.
- NexoToken fixed skins are initiated from the platform and resolved only through recognized catalog identifiers.
- The helper never changes API keys, base URLs, model channels, or billing configuration.

## Safety

- Uses a loopback-only debugging connection and does not modify the official `.app`, `app.asar`, or WindowsApps installation.
- Images, theme configuration, Safe CSS, ZIP packages, and updates have strict format, size, and integrity limits.
- Updates and theme changes use staging, atomic replacement, and recovery paths to avoid partial state.
- No system security feature is disabled. Follow the graphical first-run guide for unsigned packages.

## Development

| Platform | Source | Main entry |
|---|---|---|
| macOS | [`macos/`](./macos/) | `Install Codex Dream Skin.command` |
| Windows | [`windows/`](./windows/) | `scripts/install-dream-skin.ps1` |

Documentation:

- [Platforms and paths](./docs/platforms.md)
- [macOS development](./macos/README.md)
- [Windows development](./windows/README.en.md)
- [Project notes](./docs/PROJECT.md)

Before submitting changes, run the relevant platform test suite and ensure `tools/sync-runtime-assets.mjs --check` passes. Formal installers are built only by the automated release workflow on `main`.

## License and notices

- This is an unofficial appearance tool and is not affiliated with OpenAI. Codex, ChatGPT, and related marks belong to their respective owners.
- See [`macos/LICENSE`](./macos/LICENSE) for the open-source license and [`macos/NOTICE.md`](./macos/NOTICE.md) for retained third-party notices.
- Artwork involving people or third-party IP must have confirmed redistribution and commercial-use rights before public release.

---

NexoToken brings model access and the Codex workspace experience under one account.
