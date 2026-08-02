import Foundation

public struct NexoSkinCatalogEntry: Equatable, Sendable {
  public let id: String
  public let name: String
  public let imageURL: URL
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
    guard let record = files[id],
          let imageURL = URL(
            string: "\(assetOrigin)/codex-skins/originals/\(record.file)"
          ) else {
      return nil
    }
    return NexoSkinCatalogEntry(id: id, name: record.name, imageURL: imageURL)
  }

  public static func isRestoreURL(_ url: URL) -> Bool {
    url.absoluteString == "dreamskin://restore"
  }
}
