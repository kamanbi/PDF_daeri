// Apple App Store Server API 인증 점검. F:\keys\PDF_daeri 의 "앱 내 구입" 키로 운영·샌드박스 서버를 각각 호출해
// HTTP 상태만 보여 준다(키 값·토큰은 출력하지 않는다).
//
//   node tool/check_apple_iap_auth.mjs
//
// 해석:
//   샌드박스 404(4040010) = 인증 통과(거래만 없음)  → 키·서명은 정상
//   운영    404(4040010) = 인증 통과                 → 운영 서버가 키를 받아들임(출시 가능)
//   운영    401         = 운영 서버가 아직 이 키를 받지 않음 → 전파 대기 또는 Apple 지원 문의
import fs from 'node:fs';
import { createAppleJwt } from '../netlify/lib/apple_subscription.mjs';

const dir = 'F:/keys/PDF_daeri';
const env = fs.readFileSync(`${dir}/.env`, 'utf8');
const blocks = [...env.matchAll(/app\s*내\s*구입[\s\S]*?issuer\s*ID\s*[:：]\s*(\S+)[\s\S]*?키\s*ID\s*[:：]\s*(\S+)/gi)];
if (blocks.length === 0) throw new Error('.env에서 "app 내 구입" 블록을 찾지 못했습니다.');
const [, issuerId, keyId] = blocks[blocks.length - 1];
const privateKey = fs.readFileSync(`${dir}/SubscriptionKey_${keyId}.p8`, 'utf8');
const token = createAppleJwt({ keyId, issuerId, privateKey });

const hosts = {
  운영: 'https://api.storekit.itunes.apple.com',
  샌드박스: 'https://api.storekit-sandbox.itunes.apple.com',
};
for (const [name, host] of Object.entries(hosts)) {
  const response = await fetch(`${host}/inApps/v1/subscriptions/2000000000000001`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  let body = {};
  try {
    body = await response.json();
  } catch {
    // 본문이 없으면 상태 코드만 본다.
  }
  const verdict = response.status === 404 ? '인증 통과' : response.status === 401 ? '인증 거부' : '확인 필요';
  console.log(`${name}: HTTP ${response.status} ${body.errorCode ?? ''} → ${verdict}`);
}
