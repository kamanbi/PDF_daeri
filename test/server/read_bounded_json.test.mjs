import assert from 'node:assert/strict';
import test from 'node:test';

import { readBoundedJson } from '../../netlify/lib/read_bounded_json.mjs';

function jsonRequest(body, headers = {}) {
  return new Request('https://example.test/function', {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body,
  });
}

test('reads JSON within the configured byte limit', async () => {
  const result = await readBoundedJson(jsonRequest('{"ok":true}'), 32);
  assert.deepEqual(result, { ok: true, value: { ok: true } });
});

test('rejects a declared or streamed body larger than the configured limit', async () => {
  const declared = await readBoundedJson(jsonRequest('{}', { 'content-length': '100' }), 16);
  const streamed = await readBoundedJson(jsonRequest('{"value":"too long"}'), 8);
  assert.deepEqual(declared, { ok: false, status: 413 });
  assert.deepEqual(streamed, { ok: false, status: 413 });
});

test('requires JSON and rejects malformed or invalid UTF-8 payloads', async () => {
  const unsupported = await readBoundedJson(new Request('https://example.test', {
    method: 'POST',
    headers: { 'content-type': 'text/plain' },
    body: '{}',
  }), 32);
  const malformed = await readBoundedJson(jsonRequest('{'), 32);
  const invalidUtf8 = new Request('https://example.test', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: new Uint8Array([0xff]),
  });
  const invalidEncoding = await readBoundedJson(invalidUtf8, 32);

  assert.deepEqual(unsupported, { ok: false, status: 415 });
  assert.deepEqual(malformed, { ok: false, status: 400 });
  assert.deepEqual(invalidEncoding, { ok: false, status: 400 });
});
