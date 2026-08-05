# macOS File-Backed Device Identity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Future macOS releases create and use a private file-backed Ed25519 device identity without accessing macOS Keychain.

**Architecture:** `NexoDeviceClient` owns a small file-backed identity store beneath the existing Application Support state root. It validates the directory and identity file before loading, writes a newly generated identity atomically, and leaves legacy Keychain data untouched. The request signing and fixed HTTPS API remain unchanged.

**Tech Stack:** Swift 5.9, Foundation, CryptoKit, XCTest, Node.js source-contract tests.

---

### Task 1: Lock the public source contract

**Files:**
- Modify: `tests/nexo-device-pairing.test.mjs`

- [ ] **Step 1: Write the failing test**

```js
test('macOS keeps its Ed25519 device identity in private application support storage', () => {
  assert.match(macDevice, /device-identity\\.json/);
  assert.match(macDevice, /posixPermissions: 0o600/);
  assert.doesNotMatch(macDevice, /import Security|SecItem|kSecAttr/);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test tests/nexo-device-pairing.test.mjs`

Expected: the new test fails because the device client still imports Security and calls `SecItemCopyMatching`.

- [ ] **Step 3: Implement the file-backed store**

```swift
private static func identityURL(fileManager: FileManager) throws -> URL {
  let root = try applicationSupportRoot(fileManager: fileManager)
  return root.appendingPathComponent("device-identity.json", isDirectory: false)
}
```

Delete `import Security` and all `SecItem*` use. Use `FileManager` attributes and a temporary sibling file followed by `replaceItemAt`/`moveItem` to enforce a real `0700` state directory and a regular `0600` identity file. Leave the identity JSON and key-signing protocol unchanged.

- [ ] **Step 4: Run test to verify it passes**

Run: `node --test tests/nexo-device-pairing.test.mjs`

Expected: all source-contract tests pass.

### Task 2: Exercise file-backed identity behavior

**Files:**
- Modify: `macos/menubar-app/Package.swift`
- Modify: `macos/menubar-app/Sources/CodexDreamSkinMenuBar/NexoDeviceClient.swift`
- Create: `macos/menubar-app/Tests/CodexDreamSkinMenuBarTests/NexoDeviceIdentityTests.swift`

- [ ] **Step 1: Write failing XCTest cases**

```swift
func testNewIdentityIsPersistedWithPrivatePermissions() throws {
  let store = NexoDeviceIdentityStore(rootURL: root)
  let created = try store.loadOrCreate()
  XCTAssertEqual(created, try store.loadOrCreate())
  XCTAssertEqual(try mode(of: store.url), 0o600)
}

func testSymbolicLinkIdentityIsRejected() throws {
  try fileManager.createSymbolicLink(at: store.url, withDestinationURL: target)
  XCTAssertThrowsError(try store.loadOrCreate())
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path macos/menubar-app --filter NexoDeviceIdentityTests`

Expected: compilation fails because `NexoDeviceIdentityStore` does not exist.

- [ ] **Step 3: Extract a testable store and inject it into the client**

```swift
final class NexoDeviceIdentityStore {
  init(rootURL: URL, fileManager: FileManager = .default) { ... }
  func loadOrCreate() throws -> NexoStoredIdentity { ... }
}
```

`NexoDeviceClient` constructs this store from the standard Application Support path. The store rejects links, malformed data, invalid keys, and insecure modes; it never queries Keychain.

- [ ] **Step 4: Run focused tests to verify they pass**

Run: `swift test --package-path macos/menubar-app --filter NexoDeviceIdentityTests`

Expected: all identity tests pass.

### Task 3: Run release-scope verification and commit

**Files:**
- Modify: `TASK_PROGRESS.md`
- Modify: `docs/superpowers/specs/2026-08-05-macos-file-backed-device-identity-design.md`

- [ ] **Step 1: Run applicable regression gates**

Run:

```bash
node --test tests/nexo-device-pairing.test.mjs
swift test --package-path macos/menubar-app
CODEX_DREAM_SKIN_SKIP_DOCTOR=1 bash macos/tests/run-tests.sh
git diff --check
```

Expected: every command exits 0.

- [ ] **Step 2: Build and inspect a future DMG without installing it**

Run: `./macos/scripts/build-dmg.sh --skip-tests`

Expected: a non-empty universal DMG is created; inspection confirms the packaged device client contains no `SecItem` or `Security` reference.

- [ ] **Step 3: Record results and commit**

```bash
git add TASK_PROGRESS.md docs/superpowers macos/menubar-app tests/nexo-device-pairing.test.mjs
git commit -m "fix(macos): avoid keychain device identity prompt"
```

Do not install the DMG, edit `/Applications`, access an existing Keychain item, or restart Codex.
