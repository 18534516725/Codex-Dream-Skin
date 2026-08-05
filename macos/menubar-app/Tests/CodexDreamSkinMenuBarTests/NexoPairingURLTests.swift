import Foundation
import XCTest
@testable import CodexDreamSkinMenuBar

final class NexoPairingURLTests: XCTestCase {
  func testNexoOneClickApplyDoesNotRequireAccountPairingOrEntitlement() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/CodexDreamSkinMenuBar/AppDelegate.swift")
    let source = try String(contentsOf: sourceURL)

    XCTAssertFalse(source.contains("NexoDeviceClient"))
    XCTAssertFalse(source.contains("currentPairingStatus"))
    XCTAssertFalse(source.contains("verifyEntitlement"))
  }
}
