import assert from 'node:assert/strict';
import { generateKeyPairSync, createVerify } from 'node:crypto';
import test from 'node:test';

import {
  AppleApiError,
  classifyAppleFailure,
  createAppleJwt,
  decodeJwsPayload,
  fetchAppleSubscription,
  isActiveAppleSubscription,
  normalizePrivateKey,
  readTransactionId,
} from '../../netlify/lib/apple_subscription.mjs';

function jws(payload) {
  return `e30.${Buffer.from(JSON.stringify(payload)).toString('base64url')}.sig`;
}

function response(status, info, extra = {}) {
  return {
    data: [{
      lastTransactions: [{
        status,
        signedTransactionInfo: jws({
          productId: 'ads_removed',
          bundleId: 'com.kamanbi.pdfdaeri',
          expiresDate: Date.now() + 86_400_000,
          ...info,
        }),
        ...extra,
      }],
    }],
  };
}

test('활성(1)·유예(4) 상태만 접근을 허용하고 만료·재시도·환불은 막는다', () => {
  assert.equal(isActiveAppleSubscription(response(1, {})), true);
  assert.equal(isActiveAppleSubscription(response(4, {})), true);
  assert.equal(isActiveAppleSubscription(response(2, {})), false);
  assert.equal(isActiveAppleSubscription(response(3, {})), false);
  assert.equal(isActiveAppleSubscription(response(5, {})), false);
});

test('상품·번들이 다르거나 만료·환불된 거래는 활성이 아니다', () => {
  assert.equal(isActiveAppleSubscription(response(1, { productId: 'other' })), false);
  assert.equal(isActiveAppleSubscription(response(1, { bundleId: 'com.other.app' })), false);
  assert.equal(isActiveAppleSubscription(response(1, { expiresDate: Date.now() - 1000 })), false);
  assert.equal(isActiveAppleSubscription(response(1, { revocationDate: Date.now() - 1000 })), false);
});

test('잘못된 응답 구조는 활성이 아니다', () => {
  assert.equal(isActiveAppleSubscription(undefined), false);
  assert.equal(isActiveAppleSubscription({}), false);
  assert.equal(isActiveAppleSubscription({ data: [{ lastTransactions: [{ status: 1, signedTransactionInfo: 'x' }] }] }), false);
  assert.equal(decodeJwsPayload('a.b'), null);
  assert.equal(decodeJwsPayload('a.!!.c'), null);
});

test('거래 ID는 숫자 문자열만 허용한다', () => {
  assert.equal(readTransactionId('2000000123456789'), '2000000123456789');
  assert.equal(readTransactionId(' 123 '), '123');
  assert.equal(readTransactionId(''), null);
  assert.equal(readTransactionId('12a'), null);
  assert.equal(readTransactionId('../etc'), null);
  assert.equal(readTransactionId(123), null);
  assert.equal(readTransactionId('1'.repeat(33)), null);
});

test('JWT는 ES256이고 kid·iss·bid를 담으며 키로 검증된다', () => {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });
  const token = createAppleJwt({ keyId: 'KEY123', issuerId: 'issuer-uuid', privateKey: pem, nowMs: 1_700_000_000_000 });
  const [h, p, s] = token.split('.');
  const header = JSON.parse(Buffer.from(h, 'base64url'));
  const payload = JSON.parse(Buffer.from(p, 'base64url'));
  assert.deepEqual(header, { alg: 'ES256', kid: 'KEY123', typ: 'JWT' });
  assert.equal(payload.iss, 'issuer-uuid');
  assert.equal(payload.aud, 'appstoreconnect-v1');
  assert.equal(payload.bid, 'com.kamanbi.pdfdaeri');
  assert.equal(payload.exp - payload.iat, 1200);
  const verifier = createVerify('SHA256');
  verifier.update(`${h}.${p}`);
  assert.equal(verifier.verify({ key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(s, 'base64url')), true);
});

function credentials() {
  const { privateKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' });
  return {
    keyId: 'K',
    issuerId: 'I',
    privateKey: privateKey.export({ type: 'pkcs8', format: 'pem' }),
  };
}

function fakeFetch(handlers) {
  const calls = [];
  const impl = async (url) => {
    calls.push(url);
    const host = new URL(url).host;
    const handler = handlers[host];
    return {
      ok: handler.status === 200,
      status: handler.status,
      json: async () => handler.body,
    };
  };
  impl.calls = calls;
  return impl;
}

test('운영에서 찾으면 샌드박스는 조회하지 않는다', async () => {
  const fetchImpl = fakeFetch({
    'api.storekit.itunes.apple.com': { status: 200, body: { data: [] } },
  });
  const result = await fetchAppleSubscription({ transactionId: '1', credentials: credentials(), fetchImpl });
  assert.deepEqual(result, { data: [] });
  assert.equal(fetchImpl.calls.length, 1);
});

test('운영에서 404면 샌드박스를 조회한다(TestFlight·심사 구매)', async () => {
  const fetchImpl = fakeFetch({
    'api.storekit.itunes.apple.com': { status: 404, body: { errorCode: 4040010 } },
    'api.storekit-sandbox.itunes.apple.com': { status: 200, body: { data: ['sandbox'] } },
  });
  const result = await fetchAppleSubscription({ transactionId: '1', credentials: credentials(), fetchImpl });
  assert.deepEqual(result, { data: ['sandbox'] });
  assert.equal(fetchImpl.calls.length, 2);
});

test('두 환경 모두 404면 404 오류, 5xx는 샌드박스 없이 바로 오류로 올린다', async () => {
  const both404 = fakeFetch({
    'api.storekit.itunes.apple.com': { status: 404, body: {} },
    'api.storekit-sandbox.itunes.apple.com': { status: 404, body: {} },
  });
  await assert.rejects(
    fetchAppleSubscription({ transactionId: '1', credentials: credentials(), fetchImpl: both404 }),
    (error) => error instanceof AppleApiError && error.status === 404,
  );
  const serverError = fakeFetch({ 'api.storekit.itunes.apple.com': { status: 500, body: {} } });
  await assert.rejects(
    fetchAppleSubscription({ transactionId: '1', credentials: credentials(), fetchImpl: serverError }),
    (error) => error instanceof AppleApiError && error.status === 500,
  );
  assert.equal(serverError.calls.length, 1);
});

test('404·400만 비활성, 인증·한도·서버 오류와 네트워크 실패는 판단 불가다', () => {
  assert.equal(classifyAppleFailure(new AppleApiError(404)), 'inactive');
  assert.equal(classifyAppleFailure(new AppleApiError(400)), 'inactive');
  assert.equal(classifyAppleFailure(new AppleApiError(401)), 'unavailable');
  assert.equal(classifyAppleFailure(new AppleApiError(403)), 'unavailable');
  assert.equal(classifyAppleFailure(new AppleApiError(429)), 'unavailable');
  assert.equal(classifyAppleFailure(new AppleApiError(500)), 'unavailable');
  assert.equal(classifyAppleFailure(new Error('network')), 'unavailable');
});

test('개인 키는 base64 한 줄·PEM·\n 이스케이프 PEM 모두 같은 PEM으로 정규화한다', () => {
  const pem = '-----BEGIN PRIVATE KEY-----\nABC\n-----END PRIVATE KEY-----';
  const asBase64 = Buffer.from(pem).toString('base64');
  assert.equal(normalizePrivateKey(asBase64), pem);
  assert.equal(normalizePrivateKey(pem), pem);
  assert.equal(normalizePrivateKey(pem.replace(/\n/g, '\n')), pem);
  assert.equal(asBase64.startsWith('-'), false);
});

test('운영이 인증을 거부(401)하면 샌드박스를 조회한다(출시 전 앱)', async () => {
  const fetchImpl = fakeFetch({
    'api.storekit.itunes.apple.com': { status: 401, body: {} },
    'api.storekit-sandbox.itunes.apple.com': { status: 200, body: { data: ['sandbox'] } },
  });
  const result = await fetchAppleSubscription({ transactionId: '1', credentials: credentials(), fetchImpl });
  assert.deepEqual(result, { data: ['sandbox'] });
  assert.equal(fetchImpl.calls.length, 2);
});

test('운영 401 + 샌드박스 401이면 인증 오류로 판단 불가다', async () => {
  const fetchImpl = fakeFetch({
    'api.storekit.itunes.apple.com': { status: 401, body: {} },
    'api.storekit-sandbox.itunes.apple.com': { status: 401, body: {} },
  });
  await assert.rejects(
    fetchAppleSubscription({ transactionId: '1', credentials: credentials(), fetchImpl }),
    (error) => error instanceof AppleApiError && error.status === 401,
  );
});
