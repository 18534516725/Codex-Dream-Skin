export const FONT_STACKS = Object.freeze({
  "native-sans": '-apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Microsoft YaHei", "Segoe UI", sans-serif',
  rounded: '"SF Pro Rounded", "PingFang SC", "Microsoft YaHei UI", "Segoe UI", sans-serif',
  editorial: 'Iowan Old Style, "Songti SC", SimSun, Georgia, serif',
  "native-mono": '"SFMono-Regular", Menlo, Monaco, Consolas, "Liberation Mono", monospace',
  pixel: '"SFMono-Regular", Menlo, Monaco, Consolas, monospace',
});

const FAMILY_TOKENS = Object.freeze({
  "cinematic-cyber": { signature: "cyber", sidebarAlpha: 0.82, hoverAlpha: 0.16, selectedAlpha: 0.25 },
  "nature-healing": { signature: "nature", sidebarAlpha: 0.76, hoverAlpha: 0.12, selectedAlpha: 0.20 },
  "warm-editorial": { signature: "editorial", sidebarAlpha: 0.88, hoverAlpha: 0.10, selectedAlpha: 0.17 },
  "cartoon-stationery": { signature: "cartoon", sidebarAlpha: 0.80, hoverAlpha: 0.14, selectedAlpha: 0.23 },
  "pixel-retro": { signature: "pixel", sidebarAlpha: 0.92, hoverAlpha: 0.18, selectedAlpha: 0.30 },
  "celestial-fantasy": { signature: "celestial", sidebarAlpha: 0.78, hoverAlpha: 0.15, selectedAlpha: 0.24 },
});

function hexChannels(value, fallback) {
  const match = String(value ?? "").match(/^#([0-9a-f]{6})$/i);
  const hex = match?.[1] ?? fallback.slice(1);
  const number = Number.parseInt(hex, 16);
  return [number >> 16, (number >> 8) & 255, number & 255];
}

function rgbAlpha(channels, alpha) {
  return `rgb(${channels.join(" ")} / ${alpha})`;
}

function font(theme, key, fallback) {
  return FONT_STACKS[theme?.typography?.[key]] ?? FONT_STACKS[fallback];
}

export function buildThemeProfile(theme) {
  const family = FAMILY_TOKENS[theme?.family] ?? FAMILY_TOKENS["cinematic-cyber"];
  const colors = theme?.colors ?? {};
  const panel = hexChannels(colors.panel, "#0b1a20");
  const accent = hexChannels(colors.accent, "#7cff46");
  const line = hexChannels(colors.line, "#547267");
  return Object.freeze({
    "--ds-family-signature": family.signature,
    "--ds-font-body": font(theme, "body", "native-sans"),
    "--ds-font-title": font(theme, "title", "native-sans"),
    "--ds-font-label": font(theme, "label", "native-sans"),
    "--ds-font-code": font(theme, "code", "native-mono"),
    "--ds-sidebar-bg": rgbAlpha(panel, family.sidebarAlpha),
    "--ds-sidebar-text": colors.text ?? "#e9fff1",
    "--ds-sidebar-muted": colors.muted ?? "#9ebdb3",
    "--ds-sidebar-hover": rgbAlpha(accent, family.hoverAlpha),
    "--ds-sidebar-selected": rgbAlpha(accent, family.selectedAlpha),
    "--ds-sidebar-border": rgbAlpha(line, 0.48),
  });
}
