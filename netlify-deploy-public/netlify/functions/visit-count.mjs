import { getStore } from '@netlify/blobs';

const counterStore = getStore({
  name: 'pdf-daeri-site',
  consistency: 'strong',
});
const counterKey = 'visitor-count';
const maxWriteAttempts = 5;
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

  const count = request.method === 'POST'
      ? await incrementVisitorCount()
      : await readVisitorCount();
  return Response.json({ count }, { headers: jsonHeaders });
};

async function readVisitorCount() {
  const entry = await counterStore.getWithMetadata(counterKey, {
    consistency: 'strong',
    type: 'json',
  });
  return entry?.data?.count ?? 0;
}

async function incrementVisitorCount() {
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

  return readVisitorCount();
}
