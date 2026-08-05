# Platform Catalog Key Rotation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the production platform database the authoritative signed skin catalog so newly published skins work on macOS and Windows without being added to the helper package.

**Architecture:** Generate one replacement Ed25519 key pair. Keep the PKCS#8 private key only in the production backend environment and pin its SPKI public key in both helper platforms under a new key ID. The helper refreshes and verifies the platform catalog before resolving a skin; its embedded catalog remains an offline compatibility fallback only.

**Tech Stack:** Node.js crypto, Swift CryptoKit, Windows PowerShell/.NET, GitHub Release workflow, Express.

---

### Task 1: Generate and validate a replacement catalog key pair

**Files:**
- Modify: production `/home/ubuntu/payment-platform/.env.production` (not Git tracked)
- Test: one-off Node.js key derivation check

- [ ] **Step 1: Generate a PKCS#8 Ed25519 private key and its SPKI public key**

```bash
node --input-type=module -e 'import { generateKeyPairSync } from "node:crypto"; const { privateKey, publicKey } = generateKeyPairSync("ed25519"); console.log(JSON.stringify({ privateKeyBase64: privateKey.export({ format: "der", type: "pkcs8" }).toString("base64"), publicKeyBase64: publicKey.export({ format: "der", type: "spki" }).toString("base64") }));'
```

- [ ] **Step 2: Store only the private key on the production host**

```env
CODEX_SKIN_CATALOG_KEY_ID=nexo-skin-2026-02
CODEX_SKIN_CATALOG_SIGNING_KEY_BASE64=<generated PKCS#8 DER Base64>
```

- [ ] **Step 3: Verify the server can derive the expected public key before container recreation**

```bash
node --input-type=module -e 'import { createPrivateKey, createPublicKey } from "node:crypto"; const privateKey = createPrivateKey({ key: Buffer.from(process.env.CODEX_SKIN_CATALOG_SIGNING_KEY_BASE64, "base64"), format: "der", type: "pkcs8" }); console.log(createPublicKey(privateKey).export({ format: "der", type: "spki" }).toString("base64"));'
```

### Task 2: Pin the new public key in both helper platforms

**Files:**
- Modify: `macos/menubar-app/Sources/DreamSkinCore/NexoSkinLink.swift`
- Modify: `windows/scripts/signed-nexo-catalog.ps1`
- Modify: `macos/VERSION`, `windows/VERSION`, `macos/package.json`, `macos/scripts/common-macos.sh`, `macos/scripts/injector.mjs`, `windows/scripts/injector.mjs`
- Test: `tests/signed-nexo-catalog.test.mjs`, `windows/tests/signed-nexo-catalog.tests.ps1`

- [ ] **Step 1: Add a failing keyring-consistency test for the new key ID in the macOS and Windows sources.**

- [ ] **Step 2: Pin the same SPKI public key under `nexo-skin-2026-02` in both sources and retain the old key ID during the release transition.**

- [ ] **Step 3: Increase all six release version sources to `1.6.38`.**

- [ ] **Step 4: Run the portable signed-catalog and platform-specific release checks.**

### Task 3: Release and activate the database catalog

**Files:**
- Modify: production `/home/ubuntu/payment-platform/.env.production` only
- Deploy: backend only after the helper public key is published

- [ ] **Step 1: Commit and fast-forward push the helper keyring/version change to `main`; let the existing Release workflow produce the matching DMG and Setup.exe.**

- [ ] **Step 2: Confirm Release `v1.6.38` contains the DMG, Setup.exe, and SHA256SUMS.txt.**

- [ ] **Step 3: Deploy the platform backend by the Git-only production flow and validate `/api/codex-skins/catalog` returns a signed envelope carrying `nexo-skin-2026-02`.**

- [ ] **Step 4: Verify an existing and a database-only newly published skin resolve through the signed catalog on macOS and Windows.**
