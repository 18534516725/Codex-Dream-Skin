import CryptoKit
import Foundation
#if os(macOS)
import Darwin
#else
import Glibc
#endif

struct NexoPairingChallenge {
  let code: String
  let expiresAt: Date
}

struct NexoApplyPermit {
  let requestID: String
}

struct NexoStoredIdentity: Codable, Equatable {
  let installationID: UUID
  let privateKeyBase64: String
}

enum NexoDeviceIdentityStoreError: Error {
  case invalidStateRoot
  case insecurePermissions
  case invalidIdentity
  case identityMissing
  case ioFailure
}

final class NexoDeviceIdentityStore {
  static let maximumIdentityBytes = 4_096
  private static let identityFilename = "device-identity.json"

  let rootURL: URL
  let url: URL

  init(rootURL: URL, fileManager: FileManager = .default) {
    self.rootURL = rootURL.standardizedFileURL
    self.url = self.rootURL.appendingPathComponent(Self.identityFilename, isDirectory: false)
    _ = fileManager
  }

  func loadOrCreate() throws -> NexoStoredIdentity {
    let rootDescriptor = try openValidatedRoot()
    defer { close(rootDescriptor) }
    do {
      return try loadExistingIdentity(rootDescriptor: rootDescriptor)
    } catch NexoDeviceIdentityStoreError.identityMissing {
      return try createIdentity(rootDescriptor: rootDescriptor)
    }
  }

  private func openValidatedRoot() throws -> Int32 {
    if mkdir(rootURL.path, 0o700) != 0, errno != EEXIST {
      throw NexoDeviceIdentityStoreError.ioFailure
    }
    let descriptor = open(rootURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard descriptor >= 0 else { throw NexoDeviceIdentityStoreError.invalidStateRoot }
    do {
      try validateDescriptor(descriptor, type: mode_t(S_IFDIR), expectedMode: nil)
      guard fchmod(descriptor, 0o700) == 0 else { throw NexoDeviceIdentityStoreError.ioFailure }
      try validateDescriptor(descriptor, type: mode_t(S_IFDIR), expectedMode: 0o700)
      return descriptor
    } catch {
      close(descriptor)
      throw error
    }
  }

  private func loadExistingIdentity(rootDescriptor: Int32) throws -> NexoStoredIdentity {
    let descriptor = openat(rootDescriptor, Self.identityFilename, O_RDONLY | O_NOFOLLOW)
    if descriptor < 0 {
      if errno == ENOENT { throw NexoDeviceIdentityStoreError.identityMissing }
      throw NexoDeviceIdentityStoreError.invalidIdentity
    }
    defer { close(descriptor) }
    let size = try validateDescriptor(
      descriptor,
      type: mode_t(S_IFREG),
      expectedMode: 0o600
    )
    guard size <= Self.maximumIdentityBytes else {
      throw NexoDeviceIdentityStoreError.invalidIdentity
    }
    let identity = try JSONDecoder().decode(NexoStoredIdentity.self, from: try readAll(from: descriptor, size: size))
    guard let raw = Data(base64Encoded: identity.privateKeyBase64) else {
      throw NexoDeviceIdentityStoreError.invalidIdentity
    }
    do {
      _ = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    } catch {
      throw NexoDeviceIdentityStoreError.invalidIdentity
    }
    return identity
  }

  private func createIdentity(rootDescriptor: Int32) throws -> NexoStoredIdentity {
    let identity = NexoStoredIdentity(
      installationID: UUID(),
      privateKeyBase64: Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString()
    )
    let temporaryName = ".device-identity-\(UUID().uuidString).tmp"
    let descriptor = openat(
      rootDescriptor,
      temporaryName,
      O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,
      0o600
    )
    guard descriptor >= 0 else { throw NexoDeviceIdentityStoreError.ioFailure }
    defer {
      close(descriptor)
      _ = unlinkat(rootDescriptor, temporaryName, 0)
    }
    _ = try validateDescriptor(descriptor, type: mode_t(S_IFREG), expectedMode: nil)
    guard fchmod(descriptor, 0o600) == 0 else { throw NexoDeviceIdentityStoreError.ioFailure }
    _ = try validateDescriptor(descriptor, type: mode_t(S_IFREG), expectedMode: 0o600)
    try write(try JSONEncoder().encode(identity), to: descriptor)
    guard fsync(descriptor) == 0 else { throw NexoDeviceIdentityStoreError.ioFailure }

    if linkat(rootDescriptor, temporaryName, rootDescriptor, Self.identityFilename, 0) != 0 {
      if errno == EEXIST { return try loadExistingIdentity(rootDescriptor: rootDescriptor) }
      throw NexoDeviceIdentityStoreError.ioFailure
    }
    guard fsync(rootDescriptor) == 0 else { throw NexoDeviceIdentityStoreError.ioFailure }
    guard unlinkat(rootDescriptor, temporaryName, 0) == 0 else {
      throw NexoDeviceIdentityStoreError.ioFailure
    }
    return try loadExistingIdentity(rootDescriptor: rootDescriptor)
  }

  @discardableResult
  private func validateDescriptor(
    _ descriptor: Int32,
    type: mode_t,
    expectedMode: mode_t?
  ) throws -> Int {
    var status = stat()
    guard fstat(descriptor, &status) == 0 else { throw NexoDeviceIdentityStoreError.ioFailure }
    let mode = mode_t(status.st_mode)
    guard mode & mode_t(S_IFMT) == type, status.st_uid == getuid() else {
      throw NexoDeviceIdentityStoreError.invalidIdentity
    }
    if let expectedMode, mode & 0o777 != expectedMode {
      throw NexoDeviceIdentityStoreError.insecurePermissions
    }
    return Int(status.st_size)
  }

  private func readAll(from descriptor: Int32, size: Int) throws -> Data {
    var output = Data()
    output.reserveCapacity(size)
    while output.count < size {
      var buffer = [UInt8](repeating: 0, count: min(1024, size - output.count))
      let count = buffer.withUnsafeMutableBytes { read(descriptor, $0.baseAddress, $0.count) }
      guard count >= 0 else { throw NexoDeviceIdentityStoreError.ioFailure }
      guard count > 0 else { throw NexoDeviceIdentityStoreError.invalidIdentity }
      output.append(contentsOf: buffer.prefix(Int(count)))
    }
    return output
  }

  private func write(_ data: Data, to descriptor: Int32) throws {
    try data.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { throw NexoDeviceIdentityStoreError.ioFailure }
      var offset = 0
      while offset < bytes.count {
        #if os(macOS)
        let count = Darwin.write(descriptor, baseAddress.advanced(by: offset), bytes.count - offset)
        #else
        let count = Glibc.write(descriptor, baseAddress.advanced(by: offset), bytes.count - offset)
        #endif
        guard count > 0 else { throw NexoDeviceIdentityStoreError.ioFailure }
        offset += count
      }
    }
  }
}

enum NexoApplyOutcomeStatus: String {
  case succeeded
  case failed
}

enum NexoDeviceError: LocalizedError {
  case identityUnavailable
  case invalidResponse
  case notPaired
  case notEntitled
  case pairingExpired

  var errorDescription: String? {
    switch self {
    case .identityUnavailable: return "无法准备此设备的安全身份。"
    case .invalidResponse: return "NexoToken 没有返回可验证的助手响应。"
    case .notPaired: return "此助手尚未连接 NexoToken 账号。"
    case .notEntitled: return "当前账号尚未获得这个皮肤。"
    case .pairingExpired: return "连接码已过期，请重新连接。"
    }
  }
}

/// A deliberately narrow client for the public helper endpoints. It never accepts a
/// host, path, credential, or request body from a deep link.
final class NexoDeviceClient: NSObject, URLSessionTaskDelegate {
  private struct APIEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
  }

  private struct PairingData: Decodable {
    let pairingCode: String
    let expiresAt: String
  }

  private struct PairingStatus: Decodable {
    let status: String
  }

  private struct EntitlementData: Decodable {
    let allowed: Bool
    let requestId: String?
  }

  private static let apiRoot = URL(string: "https://nexotoken.net/api/codex-skin-devices")!
  private static let maximumResponseBytes = 65_536
  static let maximumPairingPolls = 300

  private let identity: NexoStoredIdentity?
  private let privateKey: Curve25519.Signing.PrivateKey?
  private lazy var session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 20
    configuration.httpMaximumConnectionsPerHost = 1
    configuration.httpCookieStorage = nil
    configuration.urlCredentialStorage = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
    return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
  }()

  override init() {
    var loadedIdentity: NexoStoredIdentity?
    var loadedPrivateKey: Curve25519.Signing.PrivateKey?
    do {
      let stored = try Self.loadOrCreateIdentity()
      guard let raw = Data(base64Encoded: stored.privateKeyBase64) else {
        throw NexoDeviceError.identityUnavailable
      }
      loadedIdentity = stored
      loadedPrivateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    } catch {}
    identity = loadedIdentity
    privateKey = loadedPrivateKey
    super.init()
  }

  deinit { session.invalidateAndCancel() }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }

  func startPairing(completion: @escaping (Result<NexoPairingChallenge, Error>) -> Void) {
    guard let identity, let privateKey else {
      completion(.failure(NexoDeviceError.identityUnavailable)); return
    }
    let body: [String: Any] = [
      "installationId": identity.installationID.uuidString.lowercased(),
      "platform": "macos",
      "publicKeyBase64": privateKey.publicKey.rawRepresentation.base64EncodedString(),
    ]
    send(path: "pairing/start", method: "POST", json: body) { (result: Result<PairingData, Error>) in
      completion(result.flatMap { payload in
        guard payload.pairingCode.range(of: #"^[A-HJ-NP-Z2-9]{4}-[A-HJ-NP-Z2-9]{4}$"#, options: .regularExpression) != nil,
              let expires = Self.isoFormatter.date(from: payload.expiresAt) else {
          return .failure(NexoDeviceError.invalidResponse)
        }
        return .success(NexoPairingChallenge(code: payload.pairingCode, expiresAt: expires))
      })
    }
  }

  func currentPairingStatus(completion: @escaping (Result<String, Error>) -> Void) {
    guard let identity else {
      completion(.failure(NexoDeviceError.identityUnavailable)); return
    }
    send(
      path: "pairing/\(identity.installationID.uuidString.lowercased())",
      method: "GET",
      json: nil
    ) { (result: Result<PairingStatus, Error>) in
      completion(result.flatMap { value in
        guard ["unknown", "pairing", "active", "revoked"].contains(value.status) else {
          return .failure(NexoDeviceError.invalidResponse)
        }
        return .success(value.status)
      })
    }
  }

  func waitUntilPaired(
    attempt: Int = 0,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard let identity else {
      completion(.failure(NexoDeviceError.identityUnavailable)); return
    }
    guard attempt < Self.maximumPairingPolls else {
      completion(.failure(NexoDeviceError.pairingExpired))
      return
    }
    send(
      path: "pairing/\(identity.installationID.uuidString.lowercased())",
      method: "GET",
      json: nil
    ) { (result: Result<PairingStatus, Error>) in
      switch result {
      case let .success(value) where value.status == "active": completion(.success(()))
      case let .success(value) where value.status == "pairing":
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
          self.waitUntilPaired(attempt: attempt + 1, completion: completion)
        }
      case .success: completion(.failure(NexoDeviceError.pairingExpired))
      case let .failure(error): completion(.failure(error))
      }
    }
  }

  func verifyEntitlement(
    skinID: String,
    completion: @escaping (Result<NexoApplyPermit, Error>) -> Void
  ) {
    guard Self.isSafeSkinID(skinID) else {
      completion(.failure(NexoDeviceError.invalidResponse)); return
    }
    signedSend(path: "verify-entitlement", body: ["action": "verify", "skinId": skinID]) {
      (result: Result<EntitlementData, Error>) in
      completion(result.flatMap { value in
        guard value.allowed else { return .failure(NexoDeviceError.notEntitled) }
        guard let requestID = value.requestId,
              requestID.range(of: #"^[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil else {
          return .failure(NexoDeviceError.invalidResponse)
        }
        return .success(NexoApplyPermit(requestID: requestID))
      })
    }
  }

  func reportOutcome(
    requestID: String,
    status: NexoApplyOutcomeStatus,
    failureCode: String? = nil,
    completion: @escaping (Bool) -> Void
  ) {
    guard requestID.range(of: #"^[A-Za-z0-9-]{1,64}$"#, options: .regularExpression) != nil,
          status == .succeeded || status == .failed else { completion(false); return }
    var body: [String: Any] = ["action": "report", "requestId": requestID, "status": status.rawValue]
    if status == .failed {
      let allowed = ["CODEX_NOT_FOUND", "HELPER_UPDATE_REQUIRED", "THEME_APPLY_FAILED",
        "RENDER_VERIFICATION_FAILED", "SKIN_ASSET_UNAVAILABLE", "SKIN_NOT_SUPPORTED"]
      guard let failureCode, allowed.contains(failureCode) else { completion(false); return }
      body["failureCode"] = failureCode
    }
    signedSend(path: "apply-outcomes", body: body) { (result: Result<EmptyData, Error>) in
      completion((try? result.get()) != nil)
    }
  }

  private struct EmptyData: Decodable {}

  private func signedSend<T: Decodable>(
    path: String,
    body: [String: Any],
    completion: @escaping (Result<T, Error>) -> Void
  ) {
    guard let identity, let privateKey else {
      completion(.failure(NexoDeviceError.identityUnavailable)); return
    }
    let timestamp = Self.isoFormatter.string(from: Date())
    let nonce = Self.base64URL(Data((0..<18).map { _ in UInt8.random(in: 0...255) }))
    let unsigned: [String: Any] = [
      "body": body,
      "installationId": identity.installationID.uuidString.lowercased(),
      "nonce": nonce,
      "timestamp": timestamp,
    ]
    guard JSONSerialization.isValidJSONObject(unsigned),
          let canonical = try? JSONSerialization.data(withJSONObject: unsigned, options: [.sortedKeys]),
          let signature = try? privateKey.signature(for: canonical) else {
      completion(.failure(NexoDeviceError.identityUnavailable)); return
    }
    var envelope = unsigned
    envelope["signatureBase64"] = signature.base64EncodedString()
    send(path: path, method: "POST", json: envelope, completion: completion)
  }

  private func send<T: Decodable>(
    path: String,
    method: String,
    json: [String: Any]?,
    completion: @escaping (Result<T, Error>) -> Void
  ) {
    let url = path.split(separator: "/").reduce(Self.apiRoot) {
      $0.appendingPathComponent(String($1), isDirectory: false)
    }
    guard !path.contains(".."), !path.contains("?"),
          url.scheme == "https", url.host == "nexotoken.net",
          url.path.hasPrefix("/api/codex-skin-devices/") else {
      completion(.failure(NexoDeviceError.invalidResponse)); return
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("CodexDreamSkin/device-v1", forHTTPHeaderField: "User-Agent")
    if let json {
      guard let encoded = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]) else {
        completion(.failure(NexoDeviceError.invalidResponse)); return
      }
      request.httpBody = encoded
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
    session.dataTask(with: request) { data, response, _ in
      guard let http = response as? HTTPURLResponse, http.statusCode == 200 || http.statusCode == 201,
            http.url == url, let data, data.count <= Self.maximumResponseBytes,
            let envelope = try? JSONDecoder().decode(APIEnvelope<T>.self, from: data),
            envelope.success, let value = envelope.data else {
        completion(.failure(NexoDeviceError.invalidResponse)); return
      }
      completion(.success(value))
    }.resume()
  }

  private static let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private static func isSafeSkinID(_ value: String) -> Bool {
    value.count <= 64 && value.range(of: #"^[a-z0-9]+(?:-[a-z0-9]+)*$"#, options: .regularExpression) != nil
  }

  private static func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }

  private static func loadOrCreateIdentity() throws -> NexoStoredIdentity {
    let fileManager = FileManager.default
    guard let applicationSupportURL = fileManager.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else {
      throw NexoDeviceError.identityUnavailable
    }
    let rootURL = applicationSupportURL.appendingPathComponent(
      "CodexDreamSkinStudio",
      isDirectory: true
    )
    return try NexoDeviceIdentityStore(rootURL: rootURL, fileManager: fileManager).loadOrCreate()
  }
}
