import { getStore } from '@netlify/blobs';
import { createHash } from 'node:crypto';

const counterStore = getStore({
  name: 'pdf-daeri-site',
  consistency: 'strong',
});
const totalCounterKey = 'unique-visitors/total';
const visitorMarkerPrefix = 'unique-visitors/markers';
const dailyCounterPrefix = 'unique-visitors/daily';
const maxWriteAttempts = 8;
const visitorTokenPattern = /^[a-f0-9-]{32,36}$/i;
const jsonHeaders = {
  'Cache-Control': 'no-store',
  'Content-Type': 'application/json; charset=utf-8',
};

export default async (request) => {
  if (request.method !== 'GET' && request.method !== 'POST') {
    return new Response(null, {
      status: 405,
      headers: { Allow: 'GET, POST' },
    });
  }

  const origin = request.headers.get('origin');
  const siteOrigin = new URL(request.url).origin;
  if (origin !== null && origin !== siteOrigin) {
    return Response.json({ error: '허용되지 않은 요청입니다.' }, { status: 403 });
  }

  if (request.method === 'GET') {
    return Response.json(await readVisitCounts(), { headers: jsonHeaders });
  }

  const visitorToken = await readVisitorToken(request);
  if (visitorToken === null) {
    return Response.json({ error: '유효하지 않은 방문자 정보입니다.' }, {
      status: 400,
      headers: jsonHeaders,
    });
  }

  const visitorHash = createHash('sha256').update(visitorToken).digest('hex');
  const koreaVisitDate = getKoreaVisitDate();
  await recordUniqueVisit({ visitorHash, koreaVisitDate });
  return Response.json(await readVisitCounts(koreaVisitDate), { headers: jsonHeaders });
};

async function readVisitorToken(request) {
  try {
    const { visitorToken } = await request.json();
    return typeof visitorToken === 'string' && visitorTokenPattern.test(visitorToken)
        ? visitorToken
        : null;
  } catch {
    return null;
  }
}

function getKoreaVisitDate() {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Seoul',
  }).format(new Date());
}

async function recordUniqueVisit({ visitorHash, koreaVisitDate }) {
  const [isNewTotalVisitor, isNewTodayVisitor] = await Promise.all([
    createVisitorMarker(`${visitorMarkerPrefix}/total/${visitorHash}`),
    createVisitorMarker(`${visitorMarkerPrefix}/${koreaVisitDate}/${visitorHash}`),
  ]);

  await Promise.all([
    isNewTotalVisitor ? incrementCount(totalCounterKey) : null,
    isNewTodayVisitor ? incrementCount(`${dailyCounterPrefix}/${koreaVisitDate}`) : null,
  ]);
}

async function createVisitorMarker(markerKey) {
  const result = await counterStore.setJSON(markerKey, { recordedAt: new Date().toISOString() }, {
    onlyIfNew: true,
  });
  return result.modified;
}

async function readVisitCounts(koreaVisitDate = getKoreaVisitDate()) {
  const [todayCount, totalCount] = await Promise.all([
    readCount(`${dailyCounterPrefix}/${koreaVisitDate}`),
    readCount(totalCounterKey),
  ]);
  return { todayCount, totalCount };
}

async function readCount(counterKey) {
  const entry = await counterStore.getWithMetadata(counterKey, {
    consistency: 'strong',
    type: 'json',
  });
  return entry?.data?.count ?? 0;
}

async function incrementCount(counterKey) {
  for (let attempt = 0; attempt < maxWriteAttempts; attempt += 1) {
    const entry = await counterStore.getWithMetadata(counterKey, {
      consistency: 'strong',
      type: 'json',
    });
    const currentCount = entry?.data?.count ?? 0;
    const write = entry === null
        ? await counterStore.setJSON(counterKey, { count: currentCount + 1 }, {
            onlyIfNew: true,
          })
        : await counterStore.setJSON(counterKey, { count: currentCount + 1 }, {
            onlyIfMatch: entry.etag,
          });
    if (write.modified) return currentCount + 1;
  }

  throw new Error('방문자 수를 기록하지 못했습니다.');
}
