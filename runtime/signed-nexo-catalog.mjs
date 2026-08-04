import { createPublicKey, verify } from 'node:crypto';

export const NEXO_CATALOG_URL = 'https://nexotoken.net/api/codex-skins/catalog';
export const NEXO_ASSET_ORIGIN = 'https://nexotoken.net/codex-skins/assets/';
export const MAX_SIGNED_CATALOG_BYTES = 1_048_576;

const SAFE_ID = /^[a-z0-9]+(?:-[a-z0-9]+)*$/;
const SAFE_PATH = /^([a-z0-9]+(?:-[a-z0-9]+)*)\/(v[1-9][0-9]*)\/(background|preview)\.webp$/;
const SHA256 = /^[a-f0-9]{64}$/;
const BASE64 = /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;
const ENVELOPE_KEYS = ['keyId', 'payloadBase64', 'signatureBase64'];
const PAYLOAD_KEYS = ['assetOrigin', 'catalogVersion', 'expiresAt', 'issuedAt', 'revocations', 'schemaVersion', 'skins'];
const SKIN_KEYS = ['appearance', 'backgroundPath', 'backgroundSha256', 'category', 'id', 'nameEn', 'nameZh', 'previewPath', 'previewSha256', 'tags'];

function exactObject(value, keys, name) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new TypeError(`${name} is invalid`);
  const actual = Object.keys(value).sort();
  const expected = [...keys].sort();
  if (actual.length !== expected.length || actual.some((key, index) => key !== expected[index])) throw new TypeError(`${name} schema is invalid`);
}

function boundedText(value, name, max = 120) {
  if (typeof value !== 'string' || value.length < 1 || value.length > max || value.trim() !== value || /[\u0000-\u001f\u007f-\u009f]/.test(value)) {
    throw new TypeError(`${name} is invalid`);
  }
  return value;
}

function decodeBase64(value, name, maxBytes) {
  if (typeof value !== 'string' || value.length === 0 || !BASE64.test(value)) throw new TypeError(`${name} is invalid`);
  const bytes = Buffer.from(value, 'base64');
  if (bytes.length === 0 || bytes.length > maxBytes || bytes.toString('base64') !== value) throw new TypeError(`${name} is invalid`);
  return bytes;
}

function parseDate(value, name) {
  if (typeof value !== 'string') throw new TypeError(`${name} is invalid`);
  const date = new Date(value);
  if (!Number.isFinite(date.getTime()) || date.toISOString() !== value) throw new TypeError(`${name} is invalid`);
  return date;
}

function safeId(value, name) {
  if (typeof value !== 'string' || value.length > 64 || !SAFE_ID.test(value)) throw new TypeError(`${name} is invalid`);
  return value;
}

function assetURL(path, id, kind) {
  if (typeof path !== 'string' || path.length > 160) throw new TypeError(`${kind} path is invalid`);
  const match = SAFE_PATH.exec(path);
  if (!match || match[1] !== id || match[3] !== kind) throw new TypeError(`${kind} path is invalid`);
  return new URL(path, NEXO_ASSET_ORIGIN).toString();
}

function validatePayload(payload, now, { allowExpired = false } = {}) {
  exactObject(payload, PAYLOAD_KEYS, 'catalog');
  if (payload.schemaVersion !== 1 || !Number.isSafeInteger(payload.catalogVersion) || payload.catalogVersion < 1) throw new TypeError('catalog version is invalid');
  if (payload.assetOrigin !== NEXO_ASSET_ORIGIN) throw new TypeError('catalog origin is invalid');
  const issuedAt = parseDate(payload.issuedAt, 'issuedAt');
  const expiresAt = parseDate(payload.expiresAt, 'expiresAt');
  if (expiresAt <= issuedAt || issuedAt.getTime() > now.getTime() + 300_000) throw new TypeError('catalog time range is invalid');
  const expired = expiresAt <= now;
  if (expired && !allowExpired) throw new TypeError('catalog is expired');
  if (!Array.isArray(payload.skins) || payload.skins.length > 500) throw new TypeError('catalog skins are invalid');
  const seen = new Set();
  const skins = payload.skins.map((skin) => {
    exactObject(skin, SKIN_KEYS, 'skin');
    const id = safeId(skin.id, 'skin id');
    if (seen.has(id)) throw new TypeError('duplicate skin id');
    seen.add(id);
    if (!['light', 'dark', 'adaptive'].includes(skin.appearance)) throw new TypeError('appearance is invalid');
    if (!SHA256.test(skin.backgroundSha256) || !SHA256.test(skin.previewSha256)) throw new TypeError('digest is invalid');
    if (!Array.isArray(skin.tags) || skin.tags.length > 20) throw new TypeError('tags are invalid');
    const tags = skin.tags.map((tag) => boundedText(tag, 'tag', 64));
    if (new Set(tags).size !== tags.length) throw new TypeError('duplicate tag');
    return Object.freeze({
      ...skin,
      nameZh: boundedText(skin.nameZh, 'nameZh'),
      nameEn: boundedText(skin.nameEn, 'nameEn'),
      category: boundedText(skin.category, 'category', 64),
      tags: Object.freeze([...tags]),
      backgroundURL: assetURL(skin.backgroundPath, id, 'background'),
      previewURL: assetURL(skin.previewPath, id, 'preview'),
      source: 'remote',
    });
  });
  if (!Array.isArray(payload.revocations) || payload.revocations.length > 500) throw new TypeError('revocations are invalid');
  const revocations = payload.revocations.map((id) => safeId(id, 'revoked id'));
  if (new Set(revocations).size !== revocations.length || revocations.some((id) => seen.has(id))) throw new TypeError('revocations conflict');
  return Object.freeze({
    ...payload,
    skins: Object.freeze(skins),
    revocations: Object.freeze(revocations),
    expired,
  });
}

export function verifySignedCatalogEnvelope(envelope, { keyring, now = new Date(), allowExpired = false } = {}) {
  exactObject(envelope, ENVELOPE_KEYS, 'envelope');
  const keyId = boundedText(envelope.keyId, 'keyId', 64);
  if (!/^[a-z0-9-]+$/.test(keyId)) throw new TypeError('keyId is invalid');
  const publicKeyBase64 = keyring?.[keyId];
  if (typeof publicKeyBase64 !== 'string') throw new TypeError('catalog key is not pinned');
  const payloadBytes = decodeBase64(envelope.payloadBase64, 'payload', MAX_SIGNED_CATALOG_BYTES);
  const signatureBytes = decodeBase64(envelope.signatureBase64, 'signature', 128);
  let key;
  try { key = createPublicKey({ key: Buffer.from(publicKeyBase64, 'base64'), format: 'der', type: 'spki' }); }
  catch { throw new TypeError('catalog key is invalid'); }
  if (key.asymmetricKeyType !== 'ed25519' || !verify(null, payloadBytes, key, signatureBytes)) throw new TypeError('catalog signature is invalid');
  let payload;
  try { payload = JSON.parse(payloadBytes.toString('utf8')); }
  catch { throw new TypeError('catalog JSON is invalid'); }
  return validatePayload(payload, now, { allowExpired });
}

export function resolveSignedCatalogSkin(id, { catalog, embedded = new Map(), stale = false } = {}) {
  if (typeof id !== 'string' || !SAFE_ID.test(id) || id.length > 64 || !catalog) return null;
  if (catalog.revocations.includes(id)) return null;
  const embeddedEntry = embedded instanceof Map ? embedded.get(id) : embedded[id];
  if (stale || catalog.expired) return embeddedEntry || null;
  return catalog.skins.find((skin) => skin.id === id) || embeddedEntry || null;
}
