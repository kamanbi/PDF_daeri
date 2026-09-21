import { createSign } from 'node:crypto';

const androidPublisherScope = 'https://www.googleapis.com/auth/androidpublisher';
const packageName = 'com.kamanbi.pdf_daeri';
const productId = 'ads_removed';
const activeSubscriptionStates = new Set([
  'SUBSCRIPTION_STATE_ACTIVE',
  'SUBSCRIPTION_STATE_IN_GRACE_PERIOD',
  'SUBSCRIPTION_STATE_CANCELED',
]);
const jsonHeaders = {
  'Cache-Control': 'no-store',
  'Content-Type': 'application/json; charset=utf-8',
};

let cachedAccessToken = null;

export default async (request) => {
  if (request.method !== 'POST') {
    return new Response(null, { status: 405, headers: { Allow: 'POST' } });
  }

  const origin = request.headers.get('origin');
  const siteOrigin = new URL(request.url).origin;
  if (origin !== null && origin !== siteOrigin) {
    return Response.json({ status: 'unavailable' }, { status: 403, headers: jsonHeaders });
  }

  const verificationRequest = await readVerificationRequest(request);
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
    console.error('Google Play subscription verification failed', error);
    return Response.json({ status: 'unavailable' }, { status: 503, headers: jsonHeaders });
  }
};

async function readVerificationRequest(request) {
  try {
    const body = await request.json();
    if (body?.productId !== productId || typeof body.purchaseToken !== 'string') return null;
    const purchaseToken = body.purchaseToken.trim();
    return purchaseToken.length >= 16 && purchaseToken.length <= 4096 ? { purchaseToken } : null;
  } catch {
    return null;
  }
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
    throw new Error(`Google Play API responded ${response.status}`);
  }
  return response.json();
}

function isActiveAdsRemovedSubscription(subscription) {
  if (!activeSubscriptionStates.has(subscription.subscriptionState)) return false;
  return Array.isArray(subscription.lineItems) && subscription.lineItems.some(
    (lineItem) => lineItem.productId === productId,
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
