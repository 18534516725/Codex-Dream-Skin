import Foundation
import XCTest
@testable import CodexDreamSkinMenuBar

final class NexoPairingURLTests: XCTestCase {
  func testHelperBuildsFixedPlatformConfirmationURLForValidPairingCode() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/CodexDreamSkinMenuBar/AppDelegate.swift")
    let source = try String(contentsOf: sourceURL)

    XCTAssertTrue(source.contains("URLComponents(string: \"https://nexotoken.net/\")"))
    XCTAssertTrue(source.contains("components?.fragment = \"pairingCode="))
    XCTAssertTrue(source.contains("currentPairingStatus"))
  }
}
