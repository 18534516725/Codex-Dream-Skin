import CryptoKit
import Foundation

public enum SignedNexoCatalogError: Error, Equatable, Sendable {
  case invalidEnvelope
  case unknownKey
  case invalidSignature
  case invalidCatalog
  case expired
  case rollback
  case invalidCacheLocation
  case invalidRemoteResponse
  case responseTooLarge
}

public struct SignedNexoCatalogSkin: Equatable, Sendable {
  public let id: String
  public let nameZh: String
  public let nameEn: String
  public let category: String
  public let tags: [String]
  public let appearance: String
  public let backgroundPath: String
  public let previewPath: String
  public let backgroundSha256: String
  public let previewSha256: String
  public let backgroundURL: URL
  public let previewURL: URL
}

public struct SignedNexoCatalogSnapshot: Equatable, Sendable {
  public let catalogVersion: Int64
  public let issuedAt: Date
  public let expiresAt: Date
  public let skins: [SignedNexoCatalogSkin]
  public let revocations: Set<String>
}

public struct SignedNexoCatalogState: Equatable, Sendable {
  public let snapshot: SignedNexoCatalogSnapshot
  public let isFresh: Bool
}

private struct CatalogEnvelope: Decodable {
  let keyId: String
  let payloadBase64: String
  let signatureBase64: String
}

private struct CatalogPayload: Decodable {
  let schemaVersion: Int
  let catalogVersion: Int64
  let issuedAt: String
  let expiresAt: String
  let assetOrigin: String
  let skins: [CatalogSkin]
  let revocations: [String]
}

private struct CatalogSkin: Decodable {
  let id: String
  let nameZh: String
  let nameEn: String
  let category: String
  let tags: [String]
  let appearance: String
  let backgroundPath: String
  let previewPath: String
  let backgroundSha256: String
  let previewSha256: String
}

public struct SignedNexoCatalogVerifier: Sendable {
  public static let maximumPayloadBytes = 1_048_576
  public static let assetOrigin = "https://nexotoken.net/codex-skins/assets/"

  private static let envelopeKeys = ["keyId", "payloadBase64", "signatureBase64"]
  private static let payloadKeys = [
    "assetOrigin", "catalogVersion", "expiresAt", "issuedAt", "revocations", "schemaVersion", "skins",
  ]
  private static let skinKeys = [
    "appearance", "backgroundPath", "backgroundSha256", "category", "id", "nameEn", "nameZh",
    "previewPath", "previewSha256", "tags",
  ]
  private let publicKeys: [String: Data]

  public init(publicKeys: [String: Data]) {
    self.publicKeys = publicKeys.filter { Self.isSafeID($0.key) && $0.value.count == 32 }
  }

  public func verify(
    envelopeData: Data,
    now: Date = Date(),
    allowExpired: Bool = false
  ) throws -> SignedNexoCatalogSnapshot {
    guard envelopeData.count <= SignedNexoCatalogRemote.maximumEnvelopeBytes,
          let envelopeObject = try? Self.object(from: envelopeData),
          Self.hasExactKeys(envelopeObject, Self.envelopeKeys),
          let envelope = try? JSONDecoder().decode(CatalogEnvelope.self, from: envelopeData),
          Self.isSafeID(envelope.keyId),
          let payload = Self.strictBase64(envelope.payloadBase64),
          payload.count <= Self.maximumPayloadBytes,
          let signature = Self.strictBase64(envelope.signatureBase64),
          signature.count == 64 else {
      throw SignedNexoCatalogError.invalidEnvelope
    }
    guard let rawPublicKey = publicKeys[envelope.keyId] else {
      throw SignedNexoCatalogError.unknownKey
    }
    let publicKey: Curve25519.Signing.PublicKey
    do {
      publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: rawPublicKey)
    } catch {
      throw SignedNexoCatalogError.unknownKey
    }
    guard publicKey.isValidSignature(signature, for: payload) else {
      throw SignedNexoCatalogError.invalidSignature
    }
    return try Self.validatePayload(payload, now: now, allowExpired: allowExpired)
  }

  private static func validatePayload(
    _ data: Data,
    now: Date,
    allowExpired: Bool
  ) throws -> SignedNexoCatalogSnapshot {
    guard let object = try? object(from: data),
          hasExactKeys(object, payloadKeys),
          let skinObjects = object["skins"] as? [[String: Any]],
          skinObjects.count <= 500,
          skinObjects.allSatisfy({ hasExactKeys($0, skinKeys) }),
          let payload = try? JSONDecoder().decode(CatalogPayload.self, from: data),
          payload.schemaVersion == 1,
          payload.catalogVersion > 0,
          payload.assetOrigin == assetOrigin,
          payload.revocations.count <= 500,
          let issuedAt = parseTimestamp(payload.issuedAt),
          let expiresAt = parseTimestamp(payload.expiresAt),
          expiresAt > issuedAt,
          issuedAt <= now.addingTimeInterval(300) else {
      throw SignedNexoCatalogError.invalidCatalog
    }
    if !allowExpired && expiresAt <= now {
      throw SignedNexoCatalogError.expired
    }

    var seen = Set<String>()
    var skins: [SignedNexoCatalogSkin] = []
    skins.reserveCapacity(payload.skins.count)
    for skin in payload.skins {
      guard isSafeID(skin.id), seen.insert(skin.id).inserted,
            isSafeText(skin.nameZh, maximum: 120),
            isSafeText(skin.nameEn, maximum: 120),
            isSafeText(skin.category, maximum: 64),
            ["light", "dark", "adaptive"].contains(skin.appearance),
            isAssetPath(skin.backgroundPath, skinID: skin.id, kind: "background"),
            isAssetPath(skin.previewPath, skinID: skin.id, kind: "preview"),
            isSHA256(skin.backgroundSha256), isSHA256(skin.previewSha256),
            skin.tags.count <= 20,
            skin.tags.allSatisfy({ isSafeText($0, maximum: 64) }),
            Set(skin.tags).count == skin.tags.count,
            let backgroundURL = URL(string: assetOrigin + skin.backgroundPath),
            let previewURL = URL(string: assetOrigin + skin.previewPath) else {
        throw SignedNexoCatalogError.invalidCatalog
      }
      skins.append(.init(
        id: skin.id,
        nameZh: skin.nameZh,
        nameEn: skin.nameEn,
        category: skin.category,
        tags: skin.tags,
        appearance: skin.appearance,
        backgroundPath: skin.backgroundPath,
        previewPath: skin.previewPath,
        backgroundSha256: skin.backgroundSha256,
        previewSha256: skin.previewSha256,
        backgroundURL: backgroundURL,
        previewURL: previewURL
      ))
    }

    var revocations = Set<String>()
    for id in payload.revocations {
      guard isSafeID(id), revocations.insert(id).inserted, !seen.contains(id) else {
        throw SignedNexoCatalogError.invalidCatalog
      }
    }
    return .init(
      catalogVersion: payload.catalogVersion,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
      skins: skins,
      revocations: revocations
    )
  }

  private static func object(from data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw SignedNexoCatalogError.invalidCatalog
    }
    return object
  }

  private static func hasExactKeys(_ object: [String: Any], _ expected: [String]) -> Bool {
    object.keys.sorted() == expected
  }

  private static func strictBase64(_ value: String) -> Data? {
    guard value.count <= 1_500_000, let data = Data(base64Encoded: value),
          data.base64EncodedString() == value else { return nil }
    return data
  }

  private static func parseTimestamp(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
    return date
  }

  private static func isSafeID(_ value: String) -> Bool {
    value.count <= 64
      && value.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil
  }

  private static func isSafeText(_ value: String, maximum: Int) -> Bool {
    !value.isEmpty && value.count <= maximum && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
      && value.unicodeScalars.allSatisfy { scalar in
        scalar.value >= 0x20 && !(0x7f...0x9f).contains(scalar.value)
          && !(0x202a...0x202e).contains(scalar.value)
          && !(0x2066...0x2069).contains(scalar.value)
      }
  }

  private static func isSHA256(_ value: String) -> Bool {
    value.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil
  }

  private static func isAssetPath(_ value: String, skinID: String, kind: String) -> Bool {
    value.range(
      of: "^" + NSRegularExpression.escapedPattern(for: skinID) + #"/v[1-9][0-9]*/"# + kind + #"\.webp$"#,
      options: .regularExpression
    ) != nil
  }
}

public final class SignedNexoCatalogStore: @unchecked Sendable {
  public let cacheURL: URL
  private let verifier: SignedNexoCatalogVerifier
  private let fileManager: FileManager

  public init(
    cacheURL: URL,
    verifier: SignedNexoCatalogVerifier,
    fileManager: FileManager = .default
  ) {
    self.cacheURL = cacheURL
    self.verifier = verifier
    self.fileManager = fileManager
  }

  @discardableResult
  public func install(envelopeData: Data, now: Date = Date()) throws -> SignedNexoCatalogState {
    let snapshot = try verifier.verify(envelopeData: envelopeData, now: now)
    if let existing = load(now: now) {
      if existing.snapshot.catalogVersion > snapshot.catalogVersion {
        throw SignedNexoCatalogError.rollback
      }
      if existing.snapshot.catalogVersion == snapshot.catalogVersion,
         (existing.snapshot.skins != snapshot.skins
           || existing.snapshot.revocations != snapshot.revocations) {
        throw SignedNexoCatalogError.rollback
      }
    }
    try prepareCacheParent()
    if fileManager.fileExists(atPath: cacheURL.path) {
      let values = try cacheURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
      guard values.isSymbolicLink != true, values.isRegularFile == true else {
        throw SignedNexoCatalogError.invalidCacheLocation
      }
    }
    do {
      try envelopeData.write(to: cacheURL, options: [.atomic])
      try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cacheURL.path)
    } catch {
      throw SignedNexoCatalogError.invalidCacheLocation
    }
    return .init(snapshot: snapshot, isFresh: true)
  }

  public func installRemoteResponse(
    responseURL: URL,
    statusCode: Int,
    body: Data,
    now: Date = Date()
  ) throws -> SignedNexoCatalogState {
    let envelope = try SignedNexoCatalogRemote.validatedBody(
      responseURL: responseURL,
      statusCode: statusCode,
      body: body
    )
    return try install(envelopeData: envelope, now: now)
  }

  public func load(now: Date = Date()) -> SignedNexoCatalogState? {
    guard let values = try? cacheURL.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey]),
          values.isSymbolicLink != true, values.isRegularFile == true,
          let attributes = try? fileManager.attributesOfItem(atPath: cacheURL.path),
          let size = attributes[.size] as? NSNumber,
          size.intValue <= SignedNexoCatalogRemote.maximumEnvelopeBytes,
          let data = try? Data(contentsOf: cacheURL, options: [.mappedIfSafe]),
          let snapshot = try? verifier.verify(envelopeData: data, now: now, allowExpired: true) else {
      return nil
    }
    return .init(snapshot: snapshot, isFresh: snapshot.expiresAt > now)
  }

  private func prepareCacheParent() throws {
    let parent = cacheURL.deletingLastPathComponent()
    if fileManager.fileExists(atPath: parent.path) {
      let values = try parent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard values.isDirectory == true, values.isSymbolicLink != true else {
        throw SignedNexoCatalogError.invalidCacheLocation
      }
    } else {
      try fileManager.createDirectory(
        at: parent,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
      )
    }
    try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
  }
}

public enum SignedNexoCatalogRemote {
  public static let endpoint = URL(string: "https://nexotoken.net/api/codex-skins/catalog")!
  public static let maximumEnvelopeBytes = 1_500_000

  public static func validatedBody(responseURL: URL, statusCode: Int, body: Data) throws -> Data {
    guard responseURL == endpoint, statusCode == 200 else {
      throw SignedNexoCatalogError.invalidRemoteResponse
    }
    guard !body.isEmpty, body.count <= maximumEnvelopeBytes else {
      throw SignedNexoCatalogError.responseTooLarge
    }
    guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
          root.keys.sorted() == ["data", "success"],
          root["success"] as? Bool == true,
          let envelope = root["data"] as? [String: Any],
          envelope.keys.sorted() == ["keyId", "payloadBase64", "signatureBase64"],
          let result = try? JSONSerialization.data(
            withJSONObject: envelope,
            options: [.sortedKeys, .withoutEscapingSlashes]
          ), result.count <= maximumEnvelopeBytes else {
      throw SignedNexoCatalogError.invalidRemoteResponse
    }
    return result
  }
}
