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
  public let backgroundSha256: String?
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
  let hashes: GeneratedHashes
  let theme: GeneratedTheme
}

private struct GeneratedHashes: Decodable {
  let poster: String
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

  // The matching private key is provisioned only on the platform signer. The
  // client pins the raw Ed25519 public key and fails closed for every other key.
  public static let pinnedCatalogPublicKeys: [String: Data] = [
    "nexo-skin-2026-01": Data(base64Encoded: "2ILmCQDK2Z63umFAxIm/PwIrVWTYLHwl66sFOLQo5Ls=")!,
    "nexo-skin-2026-02": Data(base64Encoded: "MCowBQYDK2VwAyEANRstEC8G0Xwbqxm9OxXI4IixeoIIyuyKnlkcTAl/O1s=")!,
  ]

  private static func catalogData() -> Data? {
    if let url = Bundle.main.url(forResource: "nexo-skin-catalog", withExtension: "json") {
      return try? Data(contentsOf: url)
    }
    return EmbeddedNexoSkinCatalog.data
  }

  private static let catalog: GeneratedCatalog? = {
    guard let data = catalogData(),
          let value = try? JSONDecoder().decode(GeneratedCatalog.self, from: data),
          value.schemaVersion == 2,
          value.assetOrigin == "https://nexotoken.net" else { return nil }
    return value
  }()

  private static func rgb(_ hex: String) -> String? {
    let value = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
    guard value.count == 6, let number = Int(value, radix: 16) else { return nil }
    return "\((number >> 16) & 255) \((number >> 8) & 255) \(number & 255)"
  }

  private static func embeddedEntry(id: String) -> NexoSkinCatalogEntry? {
    guard let catalog,
          let record = catalog.items.first(where: { $0.id == id }),
          let imageURL = URL(string: "\(catalog.assetOrigin)/codex-skins/originals/\(record.assetFile)"),
          let accent = rgb(record.theme.colors.accent),
          let secondary = rgb(record.theme.colors.secondary),
          let panel = rgb(record.theme.colors.panel),
          record.hashes.poster.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil else { return nil }
    let visual = record.theme.visual
    return NexoSkinCatalogEntry(
      id: record.id,
      name: record.name,
      imageURL: imageURL,
      appearance: record.theme.appearance,
      taskMode: record.theme.art.taskMode,
      backgroundSha256: record.hashes.poster,
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

  private static func defaultSignedCatalogState(now: Date = Date()) -> SignedNexoCatalogState? {
    guard !pinnedCatalogPublicKeys.isEmpty else { return nil }
    let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Application Support/CodexDreamSkinStudio/catalog",
      isDirectory: true
    )
    let store = SignedNexoCatalogStore(
      cacheURL: root.appendingPathComponent("signed-nexo-catalog.json"),
      verifier: SignedNexoCatalogVerifier(publicKeys: pinnedCatalogPublicKeys)
    )
    return store.load(now: now)
  }

  public static func entry(from url: URL) -> NexoSkinCatalogEntry? {
    let state = defaultSignedCatalogState()
    return entry(
      from: url,
      signedCatalog: state?.snapshot,
      catalogIsFresh: state?.isFresh ?? false
    )
  }

  public static func entry(
    from url: URL,
    signedCatalog: SignedNexoCatalogSnapshot?,
    catalogIsFresh: Bool
  ) -> NexoSkinCatalogEntry? {
    let source = url.absoluteString
    guard let expression = try? NSRegularExpression(pattern: linkPattern),
          let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
          match.range == NSRange(source.startIndex..., in: source),
          let idRange = Range(match.range(at: 1), in: source) else { return nil }
    let id = String(source[idRange])
    if signedCatalog?.revocations.contains(id) == true { return nil }
    if catalogIsFresh, let signed = signedCatalog?.skins.first(where: { $0.id == id }) {
      let embedded = embeddedEntry(id: id)
      return signedEntry(signed, embeddedVisual: embedded?.visual)
    }
    return embeddedEntry(id: id)
  }

  private static func signedEntry(
    _ record: SignedNexoCatalogSkin,
    embeddedVisual: NexoSkinVisualProfile?
  ) -> NexoSkinCatalogEntry {
    let defaultVisual = NexoSkinVisualProfile(
      accentRGB: record.appearance == "light" ? "35 90 150" : "112 192 255",
      secondaryRGB: record.appearance == "light" ? "170 90 105" : "244 190 92",
      panelRGB: record.appearance == "light" ? "238 242 247" : "19 34 53",
      glowStrength: record.appearance == "light" ? 0.36 : 0.50,
      signature: record.id.replacingOccurrences(of: "-", with: " ").uppercased(),
      focusX: 0.68,
      focusY: 0.46,
      layoutVariant: "poster-right",
      surfaceStyle: "glass",
      cornerStyle: "cut",
      motionPreset: "none",
      sidebarStyle: "navigation",
      composerStyle: "console",
      textureStyle: "grid"
    )
    return NexoSkinCatalogEntry(
      id: record.id,
      name: record.nameZh,
      imageURL: record.backgroundURL,
      appearance: record.appearance == "adaptive" ? "dark" : record.appearance,
      taskMode: record.taskMode,
      backgroundSha256: record.backgroundSha256,
      visual: record.visual ?? embeddedVisual ?? defaultVisual
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
