import assert from 'node:assert/strict';
import test from 'node:test';

import { isValidVisitorToken } from '../../netlify/lib/visitor_token.mjs';

test('accepts only canonical UUID v4 visitor tokens', () => {
  assert.equal(isValidVisitorToken('550e8400-e29b-41d4-a716-446655440000'), true);
  assert.equal(isValidVisitorToken('550e8400-e29b-11d4-a716-446655440000'), false);
  assert.equal(isValidVisitorToken('not-a-token'), false);
  assert.equal(isValidVisitorToken(null), false);
});
