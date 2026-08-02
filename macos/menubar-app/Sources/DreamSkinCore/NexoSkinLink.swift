import Foundation

public struct NexoSkinVisualProfile: Equatable, Sendable {
  public let accentRGB: String
  public let secondaryRGB: String
  public let panelRGB: String
  public let glowStrength: Double
  public let signature: String
  public let focusX: Double
  public let focusY: Double
}

public struct NexoSkinCatalogEntry: Equatable, Sendable {
  public let id: String
  public let name: String
  public let imageURL: URL
  public let appearance: String
  public let taskMode: String
  public let visual: NexoSkinVisualProfile
}

public enum NexoSkinContract {
  public static let assetOrigin = "https://nexotoken.net"

  private static let files: [String: (name: String, file: String)] = [
    "stellar-voyager": ("星核旅者", "01-stellar-voyager.webp"),
    "sakura-signal": ("樱花信使", "02-sakura-signal.webp"),
    "neon-courier": ("霓虹信使", "03-neon-courier.webp"),
    "mist-beacon": ("雾海灯塔", "04-mist-beacon.webp"),
    "rain-harbor": ("雨港余光", "05-rain-harbor.webp"),
    "crimson-forge": ("绯红铸界", "06-crimson-forge.webp"),
    "cloud-antler": ("云鹿栖境", "07-cloud-antler.webp"),
    "midnight-terminal": ("午夜终端", "08-midnight-terminal.webp"),
    "retro-orbit": ("复古轨道", "09-retro-orbit.webp"),
    "strategy-atrium": ("策略中庭", "10-strategy-atrium.webp"),
    "aurora-leviathan": ("极光巨鲸", "11-aurora-leviathan.webp"),
    "ink-ridge-guardian": ("墨岭守望", "12-ink-ridge-guardian.webp"),
  ]

  private static let profiles: [String: NexoSkinVisualProfile] = [
    "stellar-voyager": .init(accentRGB: "112 192 255", secondaryRGB: "244 190 92", panelRGB: "14 23 34", glowStrength: 0.58, signature: "STELLAR VOYAGER", focusX: 0.68, focusY: 0.46),
    "sakura-signal": .init(accentRGB: "232 151 190", secondaryRGB: "166 137 232", panelRGB: "25 20 31", glowStrength: 0.52, signature: "SAKURA SIGNAL", focusX: 0.72, focusY: 0.45),
    "neon-courier": .init(accentRGB: "244 93 202", secondaryRGB: "79 218 229", panelRGB: "23 15 31", glowStrength: 0.68, signature: "NEON COURIER", focusX: 0.66, focusY: 0.48),
    "mist-beacon": .init(accentRGB: "230 183 108", secondaryRGB: "129 164 174", panelRGB: "23 27 29", glowStrength: 0.42, signature: "MIST BEACON", focusX: 0.69, focusY: 0.45),
    "rain-harbor": .init(accentRGB: "86 190 173", secondaryRGB: "219 157 91", panelRGB: "13 24 25", glowStrength: 0.50, signature: "RAIN HARBOR", focusX: 0.72, focusY: 0.47),
    "crimson-forge": .init(accentRGB: "232 82 73", secondaryRGB: "235 170 80", panelRGB: "30 15 17", glowStrength: 0.64, signature: "CRIMSON FORGE", focusX: 0.67, focusY: 0.46),
    "cloud-antler": .init(accentRGB: "147 213 181", secondaryRGB: "190 166 231", panelRGB: "20 27 25", glowStrength: 0.44, signature: "CLOUD ANTLER", focusX: 0.70, focusY: 0.44),
    "midnight-terminal": .init(accentRGB: "84 205 162", secondaryRGB: "93 145 218", panelRGB: "12 21 20", glowStrength: 0.48, signature: "MIDNIGHT TERMINAL", focusX: 0.73, focusY: 0.49),
    "retro-orbit": .init(accentRGB: "229 137 72", secondaryRGB: "83 179 178", panelRGB: "30 22 17", glowStrength: 0.55, signature: "RETRO ORBIT", focusX: 0.69, focusY: 0.45),
    "strategy-atrium": .init(accentRGB: "205 174 105", secondaryRGB: "101 164 134", panelRGB: "28 24 18", glowStrength: 0.40, signature: "STRATEGY ATRIUM", focusX: 0.71, focusY: 0.46),
    "aurora-leviathan": .init(accentRGB: "91 210 207", secondaryRGB: "155 126 230", panelRGB: "12 25 30", glowStrength: 0.62, signature: "AURORA LEVIATHAN", focusX: 0.68, focusY: 0.42),
    "ink-ridge-guardian": .init(accentRGB: "203 166 97", secondaryRGB: "168 83 76", panelRGB: "27 23 19", glowStrength: 0.43, signature: "INK RIDGE GUARDIAN", focusX: 0.70, focusY: 0.45),
  ]

  private static let linkPattern = #"^dreamskin://apply\?skin=([a-z0-9-]{1,64})$"#

  public static func entry(from url: URL) -> NexoSkinCatalogEntry? {
    let source = url.absoluteString
    guard let expression = try? NSRegularExpression(pattern: linkPattern),
          let match = expression.firstMatch(
            in: source,
            range: NSRange(source.startIndex..., in: source)
          ),
          match.range == NSRange(source.startIndex..., in: source),
          let idRange = Range(match.range(at: 1), in: source) else {
      return nil
    }
    let id = String(source[idRange])
    guard let record = files[id], let visual = profiles[id],
          let imageURL = URL(
            string: "\(assetOrigin)/codex-skins/originals/\(record.file)"
          ) else {
      return nil
    }
    return NexoSkinCatalogEntry(
      id: id,
      name: record.name,
      imageURL: imageURL,
      appearance: "dark",
      taskMode: "full",
      visual: visual
    )
  }

  public static func isRestoreURL(_ url: URL) -> Bool {
    url.absoluteString == "dreamskin://restore"
  }
}
