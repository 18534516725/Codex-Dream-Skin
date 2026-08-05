# macOS File-Backed Device Identity

## Goal

Newly downloaded macOS releases must not ask the user to unlock or authorize a
Keychain item when the helper prepares its device identity. Preserve the
existing pairing, entitlement verification, signed request, and fixed-origin
network protocol.

This change applies to source code and future release artifacts only. It must
not edit the currently installed application, inspect or delete an existing
Keychain item, alter the user's active theme, or restart Codex.

## Chosen design

Replace the `Security.framework` generic-password item used by
`NexoDeviceClient` with one private file beneath the helper's existing state
directory:

```text
~/Library/Application Support/CodexDreamSkinStudio/device-identity.json
```

The JSON payload keeps the existing installation UUID and Ed25519 private-key
representation so the request protocol does not change. The state directory
must be a real directory owned by the current user with mode `0700`. The
identity must be a regular, non-symbolic-link file owned by the current user
with mode `0600`.

Creation uses a sibling temporary file with exclusive creation, writes the
complete encoded identity, syncs it, applies `0600`, and atomically renames it
to the canonical path. Concurrent creators re-open and validate the winning
canonical file. Temporary files are removed on recoverable failure.

Existing Keychain data is deliberately ignored and left untouched. A user who
upgrades from a Keychain-backed build receives a new file-backed identity and
must pair the helper again. This prevents the new build from causing one final
Keychain authorization prompt during migration.

## Validation and failure handling

Loading fails closed when the state directory or identity path is a symbolic
link, ownership is wrong, permissions are broader than required, the file is
oversized, JSON is malformed, the installation ID is invalid, or the private
key is not a valid Curve25519 signing key. Invalid identity data is not silently
replaced because that could hide tampering or unexpectedly sever an existing
pairing.

No secret, private-key bytes, raw file contents, or user-specific absolute path
is included in user-visible errors or logs. The existing generic
`identityUnavailable` message remains the external failure.

## Alternatives rejected

- Migrating the old Keychain item would still access it and could trigger the
  exact password dialog this change is intended to remove.
- Making the Keychain item accessible to every application would suppress
  prompts by weakening access control and is unacceptable.
- Removing device signing entirely would weaken entitlement verification and
  require an unrelated server protocol redesign.

## Tests and release acceptance

- Add a Swift testable identity store with temporary-directory tests for
  first creation, stable reload, permissions, malformed data, symlink rejection,
  and concurrent creation.
- Update portable source-contract tests to require file-backed storage and
  reject `Security`, `SecItem`, and the legacy Keychain identifiers from the
  macOS device client.
- Run focused Node and Swift tests, applicable macOS regression tests, shell
  syntax checks, and `git diff --check`.
- Build the next-version universal DMG through the repository workflow and
  verify the packaged source no longer contains Keychain access. Publishing is
  a separate release step after implementation review; no existing Release
  asset is overwritten.
