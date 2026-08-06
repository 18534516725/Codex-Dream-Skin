import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import {
  NEXO_ASSET_ORIGIN,
  resolveSignedCatalogSkin,
  verifySignedCatalogEnvelope,
} from '../runtime/signed-nexo-catalog.mjs';

const { privateKey, publicKey } = generateKeyPairSync('ed25519');
const publicKeyBase64 = publicKey.export({ format: 'der', type: 'spki' }).toString('base64');
const now = new Date('2026-08-04T00:00:00.000Z');
const root = new URL('../', import.meta.url);
const rotatedCatalogKeyId = 'nexo-skin-2026-02';
const rotatedCatalogSPKIPublicKey = 'MCowBQYDK2VwAyEANRstEC8G0Xwbqxm9OxXI4IixeoIIyuyKnlkcTAl/O1s=';
const rotatedCatalogRawPublicKey = 'NRstEC8G0Xwbqxm9OxXI4IixeoIIyuyKnlkcTAl/O1s=';

function payload(overrides = {}) {
  return {
    schemaVersion: 2,
    catalogVersion: 42,
    issuedAt: '2026-08-04T00:00:00.000Z',
    expiresAt: '2026-08-11T00:00:00.000Z',
    assetOrigin: NEXO_ASSET_ORIGIN,
    skins: [{
      id: 'aurora-field', nameZh: '极光原野', nameEn: 'Aurora Field', category: '风景', tags: ['极光'], appearance: 'dark',
      backgroundPath: 'aurora-field/v2/background.webp', previewPath: 'aurora-field/v2/preview.webp',
      backgroundSha256: 'a'.repeat(64), previewSha256: 'b'.repeat(64),
      taskMode: 'full',
      visual: {
        accentRGB: '112 192 255', secondaryRGB: '244 190 92', panelRGB: '19 34 53',
        glowStrength: 0.5, signature: 'AURORA FIELD', focusX: 0.68, focusY: 0.46,
        layoutVariant: 'poster-right', surfaceStyle: 'glass', cornerStyle: 'cut',
        motionPreset: 'none', sidebarStyle: 'navigation', composerStyle: 'console', textureStyle: 'grid',
      },
    }],
    revocations: ['retired-skin'],
    ...overrides,
  };
}

function envelope(value = payload()) {
  const bytes = Buffer.from(JSON.stringify(value));
  return {
    keyId: 'nexo-skin-2026-01',
    payloadBase64: bytes.toString('base64'),
    signatureBase64: sign(null, bytes, privateKey).toString('base64'),
  };
}

test('verifies a bounded Ed25519 envelope and derives only fixed-origin URLs', () => {
  const result = verifySignedCatalogEnvelope(envelope(), { keyring: { 'nexo-skin-2026-01': publicKeyBase64 }, now });
  assert.equal(result.skins[0].backgroundURL, `${NEXO_ASSET_ORIGIN}aurora-field/v2/background.webp`);
  assert.equal(result.skins[0].previewURL, `${NEXO_ASSET_ORIGIN}aurora-field/v2/preview.webp`);
  assert.equal(result.skins[0].visual.accentRGB, '112 192 255');
  assert.equal(result.skins[0].taskMode, 'full');
});

test('rejects incomplete or unsafe full-interface visual profiles', () => {
  const missing = payload(); delete missing.skins[0].visual.composerStyle;
  assert.throws(() => verifySignedCatalogEnvelope(envelope(missing), { keyring: { 'nexo-skin-2026-01': publicKeyBase64 }, now }));
  const unsafe = payload(); unsafe.skins[0].visual.accentRGB = '255 0 0; url(https://evil.example)';
  assert.throws(() => verifySignedCatalogEnvelope(envelope(unsafe), { keyring: { 'nexo-skin-2026-01': publicKeyBase64 }, now }));
  const outOfRange = payload(); outOfRange.skins[0].visual.focusX = 2;
  assert.throws(() => verifySignedCatalogEnvelope(envelope(outOfRange), { keyring: { 'nexo-skin-2026-01': publicKeyBase64 }, now }));
});

test('rejects tampering, wrong keys, arbitrary origins, paths, duplicate IDs, expiry and oversize payloads', () => {
  const valid = envelope();
  const tampered = { ...valid, payloadBase64: Buffer.from(JSON.stringify(payload({ catalogVersion: 43 }))).toString('base64') };
  assert.throws(() => verifySignedCatalogEnvelope(tampered, { keyring: { 'nexo-skin-2026-01': publicKeyBase64 }, now }));
  assert.throws(() => verifySignedCatalogEnvelope(valid, { keyring: {}, now }));
  assert.throws(() => verifySignedCatalogEnvelope(envelope(payload({ assetOrigin: 'https://evil.example/' })), { keyring: { 'nexo-skin-2026-01': publicKeyBase64 }, now }));
  const unsafe = payload(); unsafe.skins[0].backgroundPath = '../secret';
  assert.throws(() => verifySignedCatalogEnvelope(envelope(unsafe), { keyring: { 'nexo-skin-2026-01': publicKeyBase64 }, now }));
  const duplicate = payload(); duplicate.skins.push({ ...duplicate.skins[0] });
  assert.throws(() => verifySignedCatalogEnvelope(envelope(duplicate), { keyring: { 'nexo-skin-2026-01': publicKeyBase64 }, now }));
  assert.throws(() => verifySignedCatalogEnvelope(envelope(), { keyring: { 'nexo-skin-2026-01': publicKeyBase64 }, now: new Date('2026-08-12T00:00:00Z') }));
  assert.throws(() => verifySignedCatalogEnvelope({ ...valid, payloadBase64: Buffer.alloc(1_048_577).toString('base64') }, { keyring: { 'nexo-skin-2026-01': publicKeyBase64 }, now }));
});

test('revocation always overrides embedded fallback and stale data cannot add unknown IDs', () => {
  const verified = verifySignedCatalogEnvelope(envelope(), { keyring: { 'nexo-skin-2026-01': publicKeyBase64 }, now });
  const embedded = new Map([
    ['retired-skin', { id: 'retired-skin', source: 'embedded' }],
    ['classic-skin', { id: 'classic-skin', source: 'embedded' }],
  ]);
  assert.equal(resolveSignedCatalogSkin('retired-skin', { catalog: verified, embedded, stale: false }), null);
  assert.equal(resolveSignedCatalogSkin('classic-skin', { catalog: verified, embedded, stale: true })?.source, 'embedded');
  assert.equal(resolveSignedCatalogSkin('aurora-field', { catalog: verified, embedded, stale: true }), null);
  assert.equal(resolveSignedCatalogSkin('aurora-field', { catalog: verified, embedded, stale: false })?.source, 'remote');
});

test('unknown fields and non-canonical apply IDs fail closed', () => {
  assert.throws(() => verifySignedCatalogEnvelope(envelope({ ...payload(), extra: true }), { keyring: { 'nexo-skin-2026-01': publicKeyBase64 }, now }));
  const verified = verifySignedCatalogEnvelope(envelope(), { keyring: { 'nexo-skin-2026-01': publicKeyBase64 }, now });
  assert.equal(resolveSignedCatalogSkin('../aurora', { catalog: verified, embedded: new Map(), stale: false }), null);
});

test('platform clients bind embedded poster hashes and reject same-version content replacement', () => {
  const macLink = readFileSync(new URL('macos/menubar-app/Sources/DreamSkinCore/NexoSkinLink.swift', root), 'utf8');
  const macStore = readFileSync(new URL('macos/menubar-app/Sources/DreamSkinCore/SignedNexoCatalog.swift', root), 'utf8');
  const windowsTheme = readFileSync(new URL('windows/scripts/theme-windows.ps1', root), 'utf8');
  assert.match(macLink, /backgroundSha256: record\.hashes\.poster/);
  assert.match(windowsTheme, /BackgroundSha256 = \[string\]\$record\.hashes\.poster/);
  assert.match(macStore, /catalogVersion == snapshot\.catalogVersion/);
  assert.match(macStore, /existing\.snapshot\.revocations != snapshot\.revocations/);
  assert.match(macLink, /"nexo-skin-2026-01": Data\(base64Encoded: "[A-Za-z0-9+/]{43}="\)!/);
  const windowsSigned = readFileSync(new URL('windows/scripts/signed-nexo-catalog.ps1', root), 'utf8');
  assert.match(windowsSigned, /'nexo-skin-2026-01'\s*=\s*'MCowBQYDK2VwAyEA[A-Za-z0-9+/]{43}='/);
});

test('both platform keyrings pin the rotated production catalog public key', () => {
  const macLink = readFileSync(new URL('macos/menubar-app/Sources/DreamSkinCore/NexoSkinLink.swift', root), 'utf8');
  const windowsSigned = readFileSync(new URL('windows/scripts/signed-nexo-catalog.ps1', root), 'utf8');
  assert.match(macLink, new RegExp(`"${rotatedCatalogKeyId}": Data\\(base64Encoded: "${rotatedCatalogRawPublicKey}"\\)!`));
  assert.match(windowsSigned, new RegExp(`'${rotatedCatalogKeyId}'\\s*=\\s*'${rotatedCatalogSPKIPublicKey}'`));
});

test('both injectors extend appearance approval only from the verified signed cache', () => {
  for (const platform of ['macos', 'windows']) {
    const injector = readFileSync(new URL(`${platform}/scripts/injector.mjs`, root), 'utf8');
    assert.match(injector, /verifySignedCatalogEnvelope\(envelope, \{/);
    assert.match(injector, /allowExpired: true/);
    assert.match(injector, /for \(const skin of catalog\.skins\) APPROVED_SKIN_IDS\.add\(skin\.id\)/);
  }
  const windowsApply = readFileSync(new URL('windows/scripts/apply-community-theme.ps1', root), 'utf8');
  assert.match(windowsApply, /id = \$entry\.Id/);
  assert.doesNotMatch(windowsApply, /id = "nexo-\$\(\$entry\.Id\)"/);
});
