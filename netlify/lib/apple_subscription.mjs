import { createSign } from 'node:crypto';

// Apple App Store Server API로 `ads_removed` 구독의 활성 여부를 확인한다.
// 인증은 App Store Connect의 "앱 내 구입" 키(.p8)로 서명한 JWT(ES256)를 쓴다 — 자격증명은
// Netlify 환경 변수에만 두고 앱·저장소에는 없다.
//
// 응답의 signedTransactionInfo(JWS)는 서명 검증 없이 페이로드만 읽는다: 이 응답은 우리가 인증해서
// Apple 엔드포인트에 직접 TLS로 요청해 받은 것이라 위조될 경로가 없다(클라이언트가 보낸 값이 아니다).
// 클라이언트가 보내는 건 거래 ID뿐이고, 상품·번들·만료·환불 여부는 전부 Apple 응답으로 판정한다.

export const appleBundleId = 'com.kamanbi.pdfdaeri';
export const appleProductId = 'ads_removed';

const productionHost = 'https://api.storekit.itunes.apple.com';
const sandboxHost = 'https://api.storekit-sandbox.itunes.apple.com';

// Apple 구독 상태 코드: 1 활성, 2 만료, 3 결제 재시도 중, 4 유예 기간, 5 환불·취소.
const accessStatuses = new Set([1, 4]);

export class AppleApiError extends Error {
  constructor(status, errorCode) {
    super('Apple App Store Server API request failed');
    this.status = status;
    this.errorCode = errorCode;
  }
}

/** 클라이언트가 보낸 거래 ID가 숫자 문자열인지 검사해 정규화한다. 아니면 null. */
export function readTransactionId(value) {
  if (typeof value !== 'string') return null;
  const id = value.trim();
  return /^[0-9]{1,32}$/.test(id) ? id : null;
}

export function createAppleJwt({ keyId, issuerId, privateKey, nowMs = Date.now() }) {
  const issuedAt = Math.floor(nowMs / 1000);
  const header = toBase64Url({ alg: 'ES256', kid: keyId, typ: 'JWT' });
  const payload = toBase64Url({
    iss: issuerId,
    iat: issuedAt,
    exp: issuedAt + 1200,
    aud: 'appstoreconnect-v1',
    bid: appleBundleId,
  });
  const signer = createSign('SHA256');
  signer.update(`${header}.${payload}`);
  signer.end();
  const signature = signer.sign({ key: privateKey, dsaEncoding: 'ieee-p1363' }, 'base64url');
  return `${header}.${payload}.${signature}`;
}

export function readAppleCredentials(env = process.env) {
  const keyId = env.APPLE_IAP_KEY_ID;
  const issuerId = env.APPLE_IAP_ISSUER_ID;
  const rawKey = env.APPLE_IAP_PRIVATE_KEY;
  if (!keyId || !issuerId || !rawKey) {
    throw new Error('APPLE_IAP_KEY_ID / APPLE_IAP_ISSUER_ID / APPLE_IAP_PRIVATE_KEY are not configured');
  }
  return { keyId, issuerId, privateKey: normalizePrivateKey(rawKey) };
}

/**
 * 개인 키는 base64 한 줄(권장 — `-----`로 시작하는 값은 CLI가 옵션으로 오해해 값을 오류에 그대로 찍는다)이거나
 * PEM 원문(줄바꿈이 `\n` 두 글자로 들어온 경우 포함)일 수 있다.
 */
export function normalizePrivateKey(rawKey) {
  const key = rawKey.trim();
  if (key.startsWith('-----')) return key.replace(/\\n/g, '\n');
  return Buffer.from(key, 'base64').toString('utf8');
}

export function decodeJwsPayload(jws) {
  if (typeof jws !== 'string') return null;
  const parts = jws.split('.');
  if (parts.length !== 3) return null;
  try {
    const value = JSON.parse(Buffer.from(parts[1], 'base64url').toString('utf8'));
    return value !== null && typeof value === 'object' ? value : null;
  } catch {
    return null;
  }
}

export function isActiveAppleSubscription(response, nowMs = Date.now()) {
  if (!Array.isArray(response?.data)) return false;
  for (const group of response.data) {
    if (!Array.isArray(group?.lastTransactions)) continue;
    for (const transaction of group.lastTransactions) {
      if (!accessStatuses.has(transaction?.status)) continue;
      const info = decodeJwsPayload(transaction.signedTransactionInfo);
      if (info === null) continue;
      if (info.productId !== appleProductId || info.bundleId !== appleBundleId) continue;
      if (info.revocationDate !== undefined && info.revocationDate !== null) continue;
      if (Number(info.expiresDate) > nowMs) return true;
    }
  }
  return false;
}

/**
 * 운영 서버를 먼저 조회하고, 거래를 찾지 못하면(404) 샌드박스를 조회한다. TestFlight·App Review의
 * 구매는 샌드박스 거래라 운영 서버에는 없다.
 */
export async function fetchAppleSubscription({ transactionId, credentials, fetchImpl = fetch }) {
  const token = createAppleJwt(credentials);
  for (const host of [productionHost, sandboxHost]) {
    const response = await fetchImpl(
      `${host}/inApps/v1/subscriptions/${encodeURIComponent(transactionId)}`,
      { headers: { Accept: 'application/json', Authorization: `Bearer ${token}` } },
    );
    if (response.ok) return response.json();
    let errorCode;
    try {
      errorCode = (await response.json())?.errorCode;
    } catch {
      // 본문을 읽을 수 없는 실패는 장애로 취급한다(만료로 보지 않는다).
    }
    if (response.status === 404 && host === productionHost) continue;
    throw new AppleApiError(response.status, errorCode);
  }
  throw new AppleApiError(404);
}

/** 거래를 어느 환경에서도 찾지 못한 경우(404)와 형식 오류(400)만 비활성, 나머지는 판단 불가다. */
export function classifyAppleFailure(error) {
  return error instanceof AppleApiError && (error.status === 404 || error.status === 400)
    ? 'inactive'
    : 'unavailable';
}

function toBase64Url(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}
