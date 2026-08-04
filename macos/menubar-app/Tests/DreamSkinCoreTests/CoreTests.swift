import XCTest
import CryptoKit
@testable import DreamSkinCore

final class CoreTests: XCTestCase {
  private func signedCatalogEnvelope(
    privateKey: Curve25519.Signing.PrivateKey,
    keyID: String = "fixture-key",
    catalogVersion: Int64 = 17,
    expiresAt: String = "2026-08-11T06:00:00.000Z",
    assetOrigin: String = "https://nexotoken.net/codex-skins/assets/",
    skins: [[String: Any]]? = nil,
    revocations: [String] = []
  ) throws -> Data {
    let records = skins ?? [[
      "id": "remote-aurora",
      "nameZh": "远境极光",
      "nameEn": "Remote Aurora",
      "category": "远境",
      "tags": ["aurora", "calm"],
      "appearance": "dark",
      "backgroundPath": "remote-aurora/v3/background.webp",
      "previewPath": "remote-aurora/v3/preview.webp",
      "backgroundSha256": String(repeating: "a", count: 64),
      "previewSha256": String(repeating: "b", count: 64),
      "taskMode": "full",
      "visual": [
        "accentRGB": "112 192 255", "secondaryRGB": "244 190 92", "panelRGB": "19 34 53",
        "glowStrength": 0.5, "signature": "REMOTE AURORA", "focusX": 0.68, "focusY": 0.46,
        "layoutVariant": "poster-right", "surfaceStyle": "glass", "cornerStyle": "cut",
        "motionPreset": "none", "sidebarStyle": "navigation", "composerStyle": "console",
        "textureStyle": "grid",
      ],
    ]]
    let payloadObject: [String: Any] = [
      "schemaVersion": 2,
      "catalogVersion": catalogVersion,
      "issuedAt": "2026-08-04T06:00:00.000Z",
      "expiresAt": expiresAt,
      "assetOrigin": assetOrigin,
      "skins": records,
      "revocations": revocations,
    ]
    let payload = try JSONSerialization.data(withJSONObject: payloadObject, options: [.sortedKeys, .withoutEscapingSlashes])
    let signature = try privateKey.signature(for: payload)
    return try JSONSerialization.data(withJSONObject: [
      "keyId": keyID,
      "payloadBase64": payload.base64EncodedString(),
      "signatureBase64": signature.base64EncodedString(),
    ], options: [.sortedKeys, .withoutEscapingSlashes])
  }

  func testSemanticVersionParsingAndComparison() throws {
    XCTAssertEqual(SemanticVersion("v1.3")?.description, "1.3.0")
    XCTAssertEqual(SemanticVersion(" 2.0.1\n")?.description, "2.0.1")
    XCTAssertTrue(try XCTUnwrap(SemanticVersion("1.3.1")) > SemanticVersion("1.3.0")!)
    XCTAssertTrue(try XCTUnwrap(SemanticVersion("2.0.0")) > SemanticVersion("1.99.99")!)
    XCTAssertNil(SemanticVersion("1.3.0-beta"))
    XCTAssertNil(SemanticVersion("1..3"))
    XCTAssertNil(SemanticVersion("1.2.3.4"))
  }

  func testStatusSnapshotParsesChineseTheme() throws {
    let data = Data(#"{"session":"active","operation":"","operationMessage":"","port":9341,"injectorAlive":true,"cdpOk":true,"codexRunning":true,"themeId":"theme-cn","themeName":"中文主题","appliedThemeId":"theme-cn","appliedThemeName":"中文主题"}"#.utf8)
    let snapshot = try XCTUnwrap(StatusSnapshot(jsonData: data))
    XCTAssertEqual(snapshot.session, "active")
    XCTAssertEqual(snapshot.themeID, "theme-cn")
    XCTAssertEqual(snapshot.themeName, "中文主题")
    XCTAssertEqual(snapshot.appliedThemeID, "theme-cn")
    XCTAssertTrue(snapshot.isReadyForCommunityApply)
    XCTAssertEqual(snapshot.title, "Skin ON")
    XCTAssertFalse(snapshot.busy)
  }

  func testSavedThemesCollapseOnlyBundledAliasAndKeepCurrentSelection() {
    let themes = [
      SavedThemeOption(id: "gothic-void-crusade", name: "Gothic Void Crusade"),
      SavedThemeOption(id: "preset-gothic-void-crusade", name: "Gothic Void Crusade"),
      SavedThemeOption(id: "forest", name: "Forest"),
      SavedThemeOption(id: "preset-forest", name: "Forest")
    ]

    XCTAssertEqual(
      Set(deduplicatedSavedThemes(themes, currentThemeID: "preset-gothic-void-crusade").map(\.id)),
      Set(["preset-gothic-void-crusade", "forest", "preset-forest"])
    )
    XCTAssertEqual(
      Set(deduplicatedSavedThemes(themes, currentThemeID: "gothic-void-crusade").map(\.id)),
      Set(["gothic-void-crusade", "forest", "preset-forest"])
    )
  }

  func testBusyAndFailureLabels() {
    var snapshot = StatusSnapshot(session: "active", operation: "applying")
    XCTAssertTrue(snapshot.busy)
    XCTAssertEqual(snapshot.title, "Skin 应用中")
    snapshot.operation = "failed"
    XCTAssertEqual(snapshot.title, "Skin ON · 操作失败")
  }

  func testCommunityApplyRequiresAnExactVisibleBaseline() {
    let ready = StatusSnapshot(
      session: "active",
      port: 9341,
      injectorAlive: true,
      cdpOK: true,
      codexRunning: true,
      themeID: "old-theme",
      themeName: "Old",
      appliedThemeID: "old-theme",
      appliedThemeName: "Old"
    )
    XCTAssertTrue(ready.isReadyForCommunityApply)

    var changed = ready
    changed.appliedThemeID = "other-theme"
    XCTAssertFalse(changed.isReadyForCommunityApply)
    changed = ready
    changed.session = "paused"
    XCTAssertFalse(changed.isReadyForCommunityApply)
    changed = ready
    changed.cdpOK = false
    XCTAssertFalse(changed.isReadyForCommunityApply)
    changed = ready
    changed.operation = "applying"
    XCTAssertFalse(changed.isReadyForCommunityApply)
  }

  func testCommunityThemeLinkAcceptsOnlyCanonicalVersionLink() throws {
    let valid = try XCTUnwrap(URL(string: "dreamskin://apply?version=ver_1234abcd"))
    XCTAssertEqual(CommunityThemeContract.versionID(from: valid), "ver_1234abcd")
    XCTAssertEqual(
      CommunityThemeContract.metadataURL(for: "ver_1234abcd")?.absoluteString,
      "https://api.dreamskin.cc/v1/themes/ver_1234abcd"
    )
    XCTAssertEqual(
      CommunityThemeContract.downloadURL(for: "ver_1234abcd")?.absoluteString,
      "https://api.dreamskin.cc/v1/themes/ver_1234abcd/download"
    )

    for source in [
      "https://dreamskin.cc/apply?version=ver_1234abcd",
      "dreamskin://apply?url=https://example.com/theme.zip",
      "dreamskin://apply?version=ver_short",
      "dreamskin://apply?version=ver_1234abcd&extra=1",
      "dreamskin://apply/path?version=ver_1234abcd",
      "dreamskin://apply?version=ver_1234abcd#fragment",
      "dreamskin://user@apply?version=ver_1234abcd",
      "dreamskin://apply:443?version=ver_1234abcd",
      "DREAMSKIN://apply?version=ver_1234abcd",
      "dreamskin://apply?version=ver_1234ABCD"
    ] {
      let url = try XCTUnwrap(URL(string: source), source)
      XCTAssertNil(CommunityThemeContract.versionID(from: url), source)
    }
  }

  func testNexoSkinLinkAcceptsOnlyFixedCatalogEntries() throws {
    let valid = try XCTUnwrap(URL(string: "dreamskin://apply?skin=sakura-signal"))
    let entry = try XCTUnwrap(NexoSkinContract.entry(from: valid))
    XCTAssertEqual(entry.id, "sakura-signal")
    XCTAssertEqual(entry.name, "樱花信使")
    XCTAssertEqual(entry.appearance, "dark")
    XCTAssertEqual(entry.taskMode, "full")
    XCTAssertEqual(entry.backgroundSha256, "e25a05ba795c6f01ab562e58b8da09bc85a9ce13acf93a3c69ad93048f161738")
    XCTAssertFalse(entry.visual.accentRGB.isEmpty)
    XCTAssertFalse(entry.visual.secondaryRGB.isEmpty)
    XCTAssertFalse(entry.visual.panelRGB.isEmpty)
    XCTAssertFalse(entry.visual.signature.isEmpty)
    XCTAssertTrue((0...1).contains(entry.visual.glowStrength))
    XCTAssertTrue((0...1).contains(entry.visual.focusX))
    XCTAssertTrue((0...1).contains(entry.visual.focusY))
    XCTAssertEqual(
      entry.imageURL.absoluteString,
      "https://nexotoken.net/codex-skins/originals/02-sakura-signal.webp"
    )

    for source in [
      "dreamskin://apply?skin=unknown",
      "dreamskin://apply?skin=../sakura-signal",
      "dreamskin://apply?skin=sakura-signal&url=https://evil.example/a.webp",
      "dreamskin://apply/path?skin=sakura-signal",
      "dreamskin://apply?skin=sakura-signal#fragment",
      "https://www.nexotoken.net/apply?skin=sakura-signal"
    ] {
      XCTAssertNil(NexoSkinContract.entry(from: try XCTUnwrap(URL(string: source))), source)
    }
    XCTAssertTrue(NexoSkinContract.isCanonicalApplyURL(
      try XCTUnwrap(URL(string: "dreamskin://apply?skin=future-reviewed-skin"))
    ))
    XCTAssertFalse(NexoSkinContract.isCanonicalApplyURL(
      try XCTUnwrap(URL(string: "dreamskin://apply?skin=future-reviewed-skin&url=https://evil.example"))
    ))
    XCTAssertTrue(NexoSkinContract.isRestoreURL(try XCTUnwrap(URL(string: "dreamskin://restore"))))
    XCTAssertFalse(NexoSkinContract.isRestoreURL(try XCTUnwrap(URL(string: "dreamskin://restore?extra=1"))))
  }

  func testSignedNexoCatalogVerifiesEd25519AndResolvesOnlyFixedAssetOrigin() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let verifier = SignedNexoCatalogVerifier(publicKeys: [
      "fixture-key": privateKey.publicKey.rawRepresentation,
    ])
    let envelope = try signedCatalogEnvelope(privateKey: privateKey)

    let snapshot = try verifier.verify(
      envelopeData: envelope,
      now: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-05T06:00:00Z"))
    )
    XCTAssertEqual(snapshot.catalogVersion, 17)
    XCTAssertEqual(snapshot.skins.map(\.id), ["remote-aurora"])
    XCTAssertEqual(
      snapshot.skins.first?.backgroundURL.absoluteString,
      "https://nexotoken.net/codex-skins/assets/remote-aurora/v3/background.webp"
    )

    let applyURL = try XCTUnwrap(URL(string: "dreamskin://apply?skin=remote-aurora"))
    let entry = try XCTUnwrap(NexoSkinContract.entry(from: applyURL, signedCatalog: snapshot, catalogIsFresh: true))
    XCTAssertEqual(entry.id, "remote-aurora")
    XCTAssertEqual(entry.name, "远境极光")
    XCTAssertEqual(entry.imageURL, snapshot.skins.first?.backgroundURL)
    XCTAssertEqual(entry.backgroundSha256, String(repeating: "a", count: 64))
    XCTAssertEqual(entry.visual.accentRGB, "112 192 255")
    XCTAssertEqual(entry.visual.focusX, 0.68)
  }

  func testSignedNexoCatalogRejectsTamperingWrongKeyOriginAndUnsafePaths() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let otherKey = Curve25519.Signing.PrivateKey()
    let verifier = SignedNexoCatalogVerifier(publicKeys: [
      "fixture-key": privateKey.publicKey.rawRepresentation,
    ])
    let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-05T06:00:00Z"))

    var tampered = try XCTUnwrap(
      JSONSerialization.jsonObject(with: signedCatalogEnvelope(privateKey: privateKey)) as? [String: Any]
    )
    var payload = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(tampered["payloadBase64"] as? String)))
    payload[payload.startIndex] ^= 1
    tampered["payloadBase64"] = payload.base64EncodedString()
    XCTAssertThrowsError(try verifier.verify(
      envelopeData: JSONSerialization.data(withJSONObject: tampered),
      now: now
    ))

    XCTAssertThrowsError(try verifier.verify(
      envelopeData: signedCatalogEnvelope(privateKey: otherKey),
      now: now
    ))
    XCTAssertThrowsError(try verifier.verify(
      envelopeData: signedCatalogEnvelope(
        privateKey: privateKey,
        assetOrigin: "https://evil.example/codex-skins/assets/"
      ),
      now: now
    ))

    let futureEnvelope = try signedCatalogEnvelope(privateKey: privateKey)
    XCTAssertThrowsError(try verifier.verify(
      envelopeData: futureEnvelope,
      now: try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-04T05:00:00Z"))
    ))

    for invalidSkin in [
      [
        "id": "remote-aurora", "nameZh": "远境极光", "nameEn": "Remote Aurora", "category": "远境",
        "tags": ["calm"], "appearance": "dark", "backgroundPath": "https://evil.example/a.webp",
        "previewPath": "remote-aurora/v1/preview.webp", "backgroundSha256": String(repeating: "a", count: 64),
        "previewSha256": String(repeating: "b", count: 64),
      ],
      [
        "id": "../escape", "nameZh": "远境极光", "nameEn": "Remote Aurora", "category": "远境",
        "tags": ["calm"], "appearance": "dark", "backgroundPath": "../escape/v1/background.webp",
        "previewPath": "../escape/v1/preview.webp", "backgroundSha256": String(repeating: "a", count: 64),
        "previewSha256": String(repeating: "b", count: 64),
      ],
    ] {
      XCTAssertThrowsError(try verifier.verify(
        envelopeData: signedCatalogEnvelope(privateKey: privateKey, skins: [invalidSkin]),
        now: now
      ))
    }
  }

  func testSignedNexoCatalogCacheIsAtomicBoundedAndStaleRemoteIDsFailClosed() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let verifier = SignedNexoCatalogVerifier(publicKeys: [
      "fixture-key": privateKey.publicKey.rawRepresentation,
    ])
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let cacheURL = root.appendingPathComponent("signed-catalog.json")
    let store = SignedNexoCatalogStore(cacheURL: cacheURL, verifier: verifier)
    let freshNow = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-05T06:00:00Z"))
    let staleNow = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-12T06:00:00Z"))
    let envelope = try signedCatalogEnvelope(
      privateKey: privateKey,
      revocations: ["sakura-signal"]
    )

    let installed = try store.install(envelopeData: envelope, now: freshNow)
    XCTAssertTrue(installed.isFresh)
    XCTAssertEqual(try Data(contentsOf: cacheURL), envelope)
    XCTAssertEqual(
      (try FileManager.default.attributesOfItem(atPath: cacheURL.path)[.posixPermissions] as? NSNumber)?.intValue,
      0o600
    )

    let stale = try XCTUnwrap(store.load(now: staleNow))
    XCTAssertFalse(stale.isFresh)
    XCTAssertNil(NexoSkinContract.entry(
      from: try XCTUnwrap(URL(string: "dreamskin://apply?skin=remote-aurora")),
      signedCatalog: stale.snapshot,
      catalogIsFresh: stale.isFresh
    ))
    XCTAssertNil(NexoSkinContract.entry(
      from: try XCTUnwrap(URL(string: "dreamskin://apply?skin=sakura-signal")),
      signedCatalog: stale.snapshot,
      catalogIsFresh: stale.isFresh
    ))
    XCTAssertNotNil(NexoSkinContract.entry(
      from: try XCTUnwrap(URL(string: "dreamskin://apply?skin=stellar-voyager")),
      signedCatalog: stale.snapshot,
      catalogIsFresh: stale.isFresh
    ))
  }

  func testSignedNexoCatalogRejectsRollbackAndUnexpectedRemoteResponse() throws {
    let privateKey = Curve25519.Signing.PrivateKey()
    let verifier = SignedNexoCatalogVerifier(publicKeys: [
      "fixture-key": privateKey.publicKey.rawRepresentation,
    ])
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = SignedNexoCatalogStore(cacheURL: root.appendingPathComponent("catalog.json"), verifier: verifier)
    let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-08-05T06:00:00Z"))
    _ = try store.install(envelopeData: signedCatalogEnvelope(privateKey: privateKey, catalogVersion: 18), now: now)
    XCTAssertThrowsError(try store.install(
      envelopeData: signedCatalogEnvelope(privateKey: privateKey, catalogVersion: 17),
      now: now
    ))
    XCTAssertThrowsError(try store.install(
      envelopeData: signedCatalogEnvelope(
        privateKey: privateKey,
        catalogVersion: 18,
        revocations: ["retired-skin"]
      ),
      now: now
    ))

    XCTAssertEqual(
      SignedNexoCatalogRemote.endpoint.absoluteString,
      "https://nexotoken.net/api/codex-skins/catalog"
    )
    XCTAssertThrowsError(try SignedNexoCatalogRemote.validatedBody(
      responseURL: try XCTUnwrap(URL(string: "https://evil.example/api/codex-skins/catalog")),
      statusCode: 200,
      body: Data("{}".utf8)
    ))
    XCTAssertThrowsError(try SignedNexoCatalogRemote.validatedBody(
      responseURL: SignedNexoCatalogRemote.endpoint,
      statusCode: 200,
      body: Data(repeating: 0, count: SignedNexoCatalogRemote.maximumEnvelopeBytes + 1)
    ))
  }

  func testCommunityThemeMetadataValidatesIdentityAndBounds() throws {
    let json = #"{"id":"ver_1234abcd","themeId":"theme-one","name":"Paper","version":"1.2.3","authorDisplayName":"Author","license":"MIT","packageSha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","packageBytes":2048,"applyCompatible":true}"#
    let metadata = try JSONDecoder().decode(CommunityThemeMetadata.self, from: Data(json.utf8))
    XCTAssertEqual(try metadata.validated(expectedVersionID: "ver_1234abcd"), metadata)
    XCTAssertThrowsError(try metadata.validated(expectedVersionID: "ver_deadbeef"))

    let oversized = CommunityThemeMetadata(
      id: metadata.id,
      themeId: metadata.themeId,
      name: metadata.name,
      version: metadata.version,
      authorDisplayName: metadata.authorDisplayName,
      license: metadata.license,
      packageSha256: metadata.packageSha256,
      packageBytes: CommunityThemeContract.maximumPackageBytes + 1,
      applyCompatible: true
    )
    XCTAssertThrowsError(try oversized.validated(expectedVersionID: metadata.id))

    let legacy = CommunityThemeMetadata(
      id: metadata.id,
      themeId: metadata.themeId,
      name: metadata.name,
      version: metadata.version,
      authorDisplayName: metadata.authorDisplayName,
      license: metadata.license,
      packageSha256: metadata.packageSha256,
      packageBytes: metadata.packageBytes,
      applyCompatible: false
    )
    XCTAssertThrowsError(try legacy.validated(expectedVersionID: metadata.id)) { error in
      XCTAssertEqual(error as? CommunityThemeContractError, .incompatiblePackage)
    }

    let missingCompatibility = json.replacingOccurrences(of: #","applyCompatible":true"#, with: "")
    XCTAssertThrowsError(
      try JSONDecoder().decode(CommunityThemeMetadata.self, from: Data(missingCompatibility.utf8))
    )
    let oversizedVersion = json.replacingOccurrences(
      of: #""version":"1.2.3""#,
      with: #""version":"111111111111111111111111111111111.2.3""#
    )
    let oversizedVersionMetadata = try JSONDecoder().decode(
      CommunityThemeMetadata.self,
      from: Data(oversizedVersion.utf8)
    )
    XCTAssertThrowsError(
      try oversizedVersionMetadata.validated(expectedVersionID: oversizedVersionMetadata.id)
    )

    for unsafeName in [
      "Paper\u{061C}txt",
      "Paper\u{202E}txt",
      "Paper\u{2028}SHA-256: forged",
      "Paper\u{2066}txt\u{2069}"
    ] {
      let unsafe = CommunityThemeMetadata(
        id: metadata.id,
        themeId: metadata.themeId,
        name: unsafeName,
        version: metadata.version,
        authorDisplayName: metadata.authorDisplayName,
        license: metadata.license,
        packageSha256: metadata.packageSha256,
        packageBytes: metadata.packageBytes,
        applyCompatible: true
      )
      XCTAssertThrowsError(try unsafe.validated(expectedVersionID: metadata.id), unsafeName)
    }
  }

  func testCommunityRecoveryPreservesOnlyTheRollbackSnapshot() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
    let operation = root.appendingPathComponent(".community-apply-fixture", isDirectory: true)
    let snapshot = operation.appendingPathComponent("active-before", isDirectory: true)
    try fileManager.createDirectory(at: snapshot, withIntermediateDirectories: true)
    try Data("old-theme".utf8).write(to: snapshot.appendingPathComponent("theme.json"))
    try Data("download".utf8).write(to: operation.appendingPathComponent("theme.zip"))
    let identifier = try XCTUnwrap(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))

    let retained = try CommunityRecovery.preserveRollbackSnapshot(
      operationRoot: operation,
      stateRoot: root,
      identifier: identifier,
      fileManager: fileManager
    )

    XCTAssertEqual(
      retained,
      root.appendingPathComponent(
        "recovery/community-11111111-2222-3333-4444-555555555555/active-before",
        isDirectory: true
      )
    )
    XCTAssertEqual(try Data(contentsOf: retained.appendingPathComponent("theme.json")), Data("old-theme".utf8))
    XCTAssertTrue(fileManager.fileExists(atPath: operation.appendingPathComponent("theme.zip").path))
    XCTAssertFalse(fileManager.fileExists(atPath: snapshot.path))
  }

  func testCommunityRecoveryRejectsMissingAndLinkedRoots() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
    let missing = root.appendingPathComponent(".community-apply-missing", isDirectory: true)
    try fileManager.createDirectory(at: missing, withIntermediateDirectories: false)
    XCTAssertThrowsError(
      try CommunityRecovery.preserveRollbackSnapshot(operationRoot: missing, stateRoot: root)
    ) { error in
      XCTAssertEqual(error as? CommunityRecoveryError, .missingRollbackSnapshot)
    }

    let outside = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: outside) }
    try fileManager.createDirectory(at: outside, withIntermediateDirectories: false)
    let linked = root.appendingPathComponent(".community-apply-linked", isDirectory: true)
    try fileManager.createSymbolicLink(at: linked, withDestinationURL: outside)
    XCTAssertThrowsError(
      try CommunityRecovery.preserveRollbackSnapshot(operationRoot: linked, stateRoot: root)
    ) { error in
      XCTAssertEqual(error as? CommunityRecoveryError, .invalidOperationRoot)
    }
  }

  func testCommunityRecoveryLeavesValidatedSnapshotInPlaceWhenPromotionIsUnavailable() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: root) }
    try fileManager.createDirectory(at: root, withIntermediateDirectories: false)
    let operation = root.appendingPathComponent(".community-apply-fixture", isDirectory: true)
    let snapshot = operation.appendingPathComponent("active-before", isDirectory: true)
    try fileManager.createDirectory(at: snapshot, withIntermediateDirectories: true)
    try Data("old-theme".utf8).write(to: snapshot.appendingPathComponent("theme.json"))

    let outside = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? fileManager.removeItem(at: outside) }
    try fileManager.createDirectory(at: outside, withIntermediateDirectories: false)
    try fileManager.createSymbolicLink(
      at: root.appendingPathComponent("recovery", isDirectory: true),
      withDestinationURL: outside
    )

    XCTAssertThrowsError(
      try CommunityRecovery.preserveRollbackSnapshot(operationRoot: operation, stateRoot: root)
    ) { error in
      XCTAssertEqual(error as? CommunityRecoveryError, .invalidRecoveryRoot)
    }
    XCTAssertEqual(
      try CommunityRecovery.validatedRollbackSnapshot(operationRoot: operation, stateRoot: root),
      snapshot
    )
    XCTAssertEqual(try Data(contentsOf: snapshot.appendingPathComponent("theme.json")), Data("old-theme".utf8))
  }
}
