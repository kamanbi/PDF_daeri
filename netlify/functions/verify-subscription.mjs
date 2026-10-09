import { createSign } from 'node:crypto';
import {
  AppleApiError,
  appleProductId,
  classifyAppleFailure,
  fetchAppleSubscription,
  isActiveAppleSubscription,
  readAppleCredentials,
  readTransactionId,
} from '../lib/apple_subscription.mjs';
import { readBoundedJson } from '../lib/read_bounded_json.mjs';

const androidPublisherScope = 'https://www.googleapis.com/auth/androidpublisher';
const packageName = 'com.kamanbi.pdf_daeri';
const productId = 'ads_removed';
export const maximumRequestBytes = 8 * 1024;
const activeSubscriptionStates = new Set([
  'SUBSCRIPTION_STATE_ACTIVE',
  'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
  'SUBSCRIPTION_STATE_CANCELED',
]);
const permanentlyInvalidTokenReasons = new Set([
  'purchaseTokenNoLongerValid',
  'subscriptionNoLongerAvailable',
  'subscriptionExpired',
]);
const jsonHeaders = {
  'Cache-Control': 'no-store',
  'Content-Type': 'application/json; charset=utf-8',
};

let cachedAccessToken = null;

// 호출자 인증이 없는 공개 엔드포인트라 rate limit이 유일한 남용 방지선이다(전체 앱 보안 감사
// M-B). 임의의 요청으로 Google Play API 할당량을 소진시키면 신규 구매자 검증까지 503으로
// 막힐 수 있어, IP 기준으로 분당 호출 수를 제한한다. 정상 사용(앱 실행 시 확인, 구매 직후
// 확인, 복원)은 분당 30회면 충분히 여유 있다.
export const config = {
  path: '/.netlify/functions/verify-subscription',
  rateLimit: {
    windowSize: 60,
    windowLimit: 30,
    aggregateBy: ['ip', 'domain'],
  },
};

export default async (request) => {
  if (request.method !== 'POST') {
    return new Response(null, { status: 405, headers: { Allow: 'POST' } });
  }

  const origin = request.headers.get('origin');
  const siteOrigin = new URL(request.url).origin;
  if (origin !== null && origin !== siteOrigin) {
    return Response.json({ status: 'unavailable' }, { status: 403, headers: jsonHeaders });
  }

  const parsedBody = await readBoundedJson(request, maximumRequestBytes);
  if (!parsedBody.ok) {
    return Response.json({ status: 'unavailable' }, {
      status: parsedBody.status,
      headers: jsonHeaders,
    });
  }
  if (parsedBody.value?.platform === 'ios') return verifyApple(parsedBody.value);

  const verificationRequest = readVerificationRequest(parsedBody.value);
  if (verificationRequest === null) {
    return Response.json({ status: 'unavailable' }, { status: 400, headers: jsonHeaders });
  }

  try {
    const subscription = await fetchSubscription(verificationRequest.purchaseToken);
    const active = isActiveAdsRemovedSubscription(subscription);
    return Response.json(
      { status: active ? 'active' : 'inactive' },
      { headers: jsonHeaders },
    );
  } catch (error) {
    const failure = classifyGooglePlayFailure(error);
    if (failure === 'inactive') {
      return Response.json({ status: 'inactive' }, { headers: jsonHeaders });
    }
    console.error('Google Play subscription verification unavailable', {
      errorType: error instanceof Error ? error.name : 'unknown',
      httpStatus: error instanceof GooglePlayApiError ? error.status : undefined,
    });
    return Response.json({ status: 'unavailable' }, { status: 503, headers: jsonHeaders });
  }
};

/** iOS: 앱이 보낸 거래 ID로 Apple App Store Server API를 조회한다(`netlify/lib/apple_subscription.mjs`). */
async function verifyApple(body) {
  const transactionId = readTransactionId(body.transactionId);
  if (body.productId !== appleProductId || transactionId === null) {
    return Response.json({ status: 'unavailable' }, { status: 400, headers: jsonHeaders });
  }
  try {
    const subscription = await fetchAppleSubscription({
      transactionId,
      credentials: readAppleCredentials(),
    });
    return Response.json(
      { status: isActiveAppleSubscription(subscription) ? 'active' : 'inactive' },
      { headers: jsonHeaders },
    );
  } catch (error) {
    if (classifyAppleFailure(error) === 'inactive') {
      return Response.json({ status: 'inactive' }, { headers: jsonHeaders });
    }
    console.error('Apple subscription verification unavailable', {
      errorType: error instanceof Error ? error.name : 'unknown',
      httpStatus: error instanceof AppleApiError ? error.status : undefined,
      errorCode: error instanceof AppleApiError ? error.errorCode : undefined,
    });
    return Response.json({ status: 'unavailable' }, { status: 503, headers: jsonHeaders });
  }
}

function readVerificationRequest(body) {
  if (body?.productId !== productId || typeof body.purchaseToken !== 'string') return null;
  const purchaseToken = body.purchaseToken.trim();
  return purchaseToken.length >= 16 && purchaseToken.length <= 4096 ? { purchaseToken } : null;
}

async function fetchSubscription(purchaseToken) {
  const accessToken = await getAccessToken();
  const url = new URL(
    `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${packageName}/purchases/subscriptionsv2/tokens/${encodeURIComponent(purchaseToken)}`,
  );
  const response = await fetch(url, {
    headers: {
      Accept: 'application/json',
      Authorization: `Bearer ${accessToken}`,
    },
  });
  if (!response.ok) {
    let errorBody = {};
    try {
      errorBody = await response.json();
    } catch {
      // An unparseable upstream failure is treated as unavailable, never as revoked.
    }
    const reasons = Array.isArray(errorBody?.error?.errors)
      ? errorBody.error.errors.map((entry) => entry?.reason).filter((reason) => typeof reason === 'string')
      : [];
    throw new GooglePlayApiError(response.status, reasons);
  }
  return response.json();
}

export class GooglePlayApiError extends Error {
  constructor(status, reasons = []) {
    super('Google Play API request failed');
    this.status = status;
    this.reasons = reasons;
  }
}

export function classifyGooglePlayFailure(error) {
  return error instanceof GooglePlayApiError && error.status === 410 &&
      error.reasons.some((reason) => permanentlyInvalidTokenReasons.has(reason))
    ? 'inactive'
    : 'unavailable';
}

export function isActiveAdsRemovedSubscription(subscription) {
  if (!activeSubscriptionStates.has(subscription.subscriptionState)) return false;
  return Array.isArray(subscription.lineItems) && subscription.lineItems.some(
    (lineItem) => lineItem.productId === productId &&
      typeof lineItem.expiryTime === 'string' &&
      Date.parse(lineItem.expiryTime) > Date.now(),
  );
}

async function getAccessToken() {
  if (cachedAccessToken !== null && cachedAccessToken.expiresAt > Date.now() + 60_000) {
    return cachedAccessToken.value;
  }

  const credentials = readServiceAccountCredentials();
  const assertion = createServiceAccountAssertion(credentials);
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion,
    }),
  });
  if (!response.ok) throw new Error(`Google OAuth responded ${response.status}`);

  const token = await response.json();
  if (typeof token.access_token !== 'string' || typeof token.expires_in !== 'number') {
    throw new Error('Google OAuth response was invalid');
  }
  cachedAccessToken = {
    value: token.access_token,
    expiresAt: Date.now() + token.expires_in * 1000,
  };
  return cachedAccessToken.value;
}

function readServiceAccountCredentials() {
  const rawCredentials = process.env.GOOGLE_PLAY_SERVICE_ACCOUNT_JSON;
  if (!rawCredentials) throw new Error('GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is not configured');

  const credentials = JSON.parse(rawCredentials);
  if (
    credentials.type !== 'service_account' ||
    typeof credentials.client_email !== 'string' ||
    typeof credentials.private_key !== 'string'
  ) {
    throw new Error('Google Play service account credentials are invalid');
  }
  return credentials;
}

function createServiceAccountAssertion(credentials) {
  const nowSeconds = Math.floor(Date.now() / 1000);
  const encodedHeader = toBase64Url({ alg: 'RS256', typ: 'JWT' });
  const encodedPayload = toBase64Url({
    iss: credentials.client_email,
    scope: androidPublisherScope,
    aud: 'https://oauth2.googleapis.com/token',
    iat: nowSeconds,
    exp: nowSeconds + 3600,
  });
  const unsignedAssertion = `${encodedHeader}.${encodedPayload}`;
  const signer = createSign('RSA-SHA256');
  signer.update(unsignedAssertion);
  signer.end();
  return `${unsignedAssertion}.${signer.sign(credentials.private_key, 'base64url')}`;
}

function toBase64Url(value) {
  return Buffer.from(JSON.stringify(value)).toString('base64url');
}
