import Foundation

public struct NexoSkinVisualProfile: Equatable, Sendable {
  public let accentRGB: String
  public let secondaryRGB: String
  public let panelRGB: String
  public let glowStrength: Double
  public let signature: String
  public let focusX: Double
  public let focusY: Double
  public let layoutVariant: String
  public let surfaceStyle: String
  public let cornerStyle: String
  public let motionPreset: String
  public let sidebarStyle: String
  public let composerStyle: String
  public let textureStyle: String
}

public struct NexoSkinCatalogEntry: Equatable, Sendable {
  public let id: String
  public let name: String
  public let imageURL: URL
  public let appearance: String
  public let taskMode: String
  public let visual: NexoSkinVisualProfile
}

private struct GeneratedCatalog: Decodable {
  let schemaVersion: Int
  let assetOrigin: String
  let items: [GeneratedItem]
}

private struct GeneratedItem: Decodable {
  let id: String
  let name: String
  let assetFile: String
  let theme: GeneratedTheme
}

private struct GeneratedTheme: Decodable {
  let appearance: String
  let family: String
  let colors: GeneratedColors
  let art: GeneratedArt
  let visual: GeneratedVisual
}

private struct GeneratedColors: Decodable {
  let panel: String
  let accent: String
  let secondary: String
}

private struct GeneratedArt: Decodable {
  let focusX: Double
  let focusY: Double
  let taskMode: String
}

private struct GeneratedVisual: Decodable {
  let layout: String
  let surface: String
  let corners: String
  let motion: String
  let sidebar: String
  let composer: String
  let texture: String
}

public enum NexoSkinContract {
  private static let linkPattern = #"^dreamskin://apply\?skin=([a-z0-9-]{1,64})$"#

  private static func catalogURL() -> URL? {
    if let url = Bundle.main.url(forResource: "nexo-skin-catalog", withExtension: "json") {
      return url
    }

    // SwiftPM test products keep resources in a sibling bundle. Resolve it
    // without Bundle.module because its generated accessor calls fatalError
    // when a hand-built app accidentally omits that bundle.
    guard let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent() else {
      return nil
    }
    let resourceBundle = executableDirectory.appendingPathComponent("CodexDreamSkinMenuBar_DreamSkinCore.bundle", isDirectory: true)
    return Bundle(url: resourceBundle)?.url(forResource: "nexo-skin-catalog", withExtension: "json")
  }

  private static let catalog: GeneratedCatalog? = {
    guard let url = catalogURL(),
          let data = try? Data(contentsOf: url),
          let value = try? JSONDecoder().decode(GeneratedCatalog.self, from: data),
          value.schemaVersion == 2,
          URL(string: value.assetOrigin)?.scheme == "https" else { return nil }
    return value
  }()

  private static func rgb(_ hex: String) -> String? {
    let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard value.count == 6, let number = Int(value, radix: 16) else { return nil }
    return "\((number >> 16) & 255) \((number >> 8) & 255) \(number & 255)"
  }

  public static func entry(from url: URL) -> NexoSkinCatalogEntry? {
    let source = url.absoluteString
    guard let expression = try? NSRegularExpression(pattern: linkPattern),
          let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
          match.range == NSRange(source.startIndex..., in: source),
          let idRange = Range(match.range(at: 1), in: source),
          let catalog else { return nil }
    let id = String(source[idRange])
    guard let record = catalog.items.first(where: { $0.id == id }),
          let imageURL = URL(string: "\(catalog.assetOrigin)/codex-skins/originals/\(record.assetFile)"),
          let accent = rgb(record.theme.colors.accent),
          let secondary = rgb(record.theme.colors.secondary),
          let panel = rgb(record.theme.colors.panel) else { return nil }
    let visual = record.theme.visual
    return NexoSkinCatalogEntry(
      id: record.id,
      name: record.name,
      imageURL: imageURL,
      appearance: record.theme.appearance,
      taskMode: record.theme.art.taskMode,
      visual: .init(
        accentRGB: accent,
        secondaryRGB: secondary,
        panelRGB: panel,
        glowStrength: record.theme.family == "cinematic-cyber" ? 0.64 : 0.50,
        signature: record.id.replacingOccurrences(of: "-", with: " ").uppercased(),
        focusX: record.theme.art.focusX,
        focusY: record.theme.art.focusY,
        layoutVariant: visual.layout,
        surfaceStyle: visual.surface,
        cornerStyle: visual.corners,
        motionPreset: visual.motion,
        sidebarStyle: visual.sidebar,
        composerStyle: visual.composer,
        textureStyle: visual.texture
      )
    )
  }

  public static func isCanonicalApplyURL(_ url: URL) -> Bool {
    let source = url.absoluteString
    guard let expression = try? NSRegularExpression(pattern: linkPattern),
          let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) else {
      return false
    }
    return match.range == NSRange(source.startIndex..., in: source)
  }

  public static func isRestoreURL(_ url: URL) -> Bool {
    url.absoluteString == "dreamskin://restore"
  }
}
