import Foundation
import XCTest
@testable import CodexDreamSkinMenuBar

final class NexoDeviceIdentityTests: XCTestCase {
  private var fileManager: FileManager!
  private var root: URL!

  override func setUpWithError() throws {
    fileManager = FileManager.default
    root = fileManager.temporaryDirectory
      .appendingPathComponent("NexoDeviceIdentityTests-\(UUID().uuidString)", isDirectory: true)
  }

  override func tearDownWithError() throws {
    if fileManager.fileExists(atPath: root.path) {
      try fileManager.removeItem(at: root)
    }
  }

  func testNewIdentityIsPersistedWithPrivatePermissions() throws {
    let store = NexoDeviceIdentityStore(rootURL: root, fileManager: fileManager)

    let created = try store.loadOrCreate()
    let reloaded = try store.loadOrCreate()

    XCTAssertEqual(created, reloaded)
    XCTAssertEqual(try mode(of: root), 0o700)
    XCTAssertEqual(try mode(of: store.url), 0o600)
    XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: root.path), ["device-identity.json"])
  }

  func testSymbolicLinkIdentityIsRejected() throws {
    let store = NexoDeviceIdentityStore(rootURL: root, fileManager: fileManager)
    try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    let target = root.appendingPathComponent("target.json", isDirectory: false)
    try Data("not an identity".utf8).write(to: target)
    try fileManager.createSymbolicLink(at: store.url, withDestinationURL: target)

    XCTAssertThrowsError(try store.loadOrCreate())
  }

  func testMalformedIdentityIsRejected() throws {
    let store = NexoDeviceIdentityStore(rootURL: root, fileManager: fileManager)
    _ = try store.loadOrCreate()
    try Data("not valid JSON".utf8).write(to: store.url)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.url.path)

    XCTAssertThrowsError(try store.loadOrCreate())
  }

  func testStateRootSymbolicLinkIsRejected() throws {
    let target = fileManager.temporaryDirectory
      .appendingPathComponent("NexoDeviceIdentityTarget-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: target) }
    try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
    try fileManager.createSymbolicLink(at: root, withDestinationURL: target)

    XCTAssertThrowsError(try NexoDeviceIdentityStore(rootURL: root, fileManager: fileManager).loadOrCreate())
  }

  func testInsecureIdentityModeIsRejected() throws {
    let store = NexoDeviceIdentityStore(rootURL: root, fileManager: fileManager)
    _ = try store.loadOrCreate()
    try fileManager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.url.path)

    XCTAssertThrowsError(try store.loadOrCreate())
  }

  func testOversizedIdentityIsRejectedBeforeDecoding() throws {
    let store = NexoDeviceIdentityStore(rootURL: root, fileManager: fileManager)
    _ = try store.loadOrCreate()
    try Data(repeating: 0, count: NexoDeviceIdentityStore.maximumIdentityBytes + 1).write(to: store.url)
    try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.url.path)

    XCTAssertThrowsError(try store.loadOrCreate())
  }

  func testConcurrentCreationReturnsOnePersistedIdentity() throws {
    let lock = NSLock()
    var results: [Result<NexoStoredIdentity, Error>] = []

    DispatchQueue.concurrentPerform(iterations: 8) { _ in
      let result = Result {
        try NexoDeviceIdentityStore(rootURL: self.root, fileManager: self.fileManager).loadOrCreate()
      }
      lock.lock()
      results.append(result)
      lock.unlock()
    }

    let identities = try results.map { try $0.get() }
    XCTAssertEqual(Set(identities.map(\.installationID)).count, 1)
  }

  private func mode(of url: URL) throws -> Int {
    let attributes = try fileManager.attributesOfItem(atPath: url.path)
    return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
  }
}
