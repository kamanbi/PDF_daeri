import assert from 'node:assert/strict';
import test from 'node:test';

import {
  classifyGooglePlayFailure,
  GooglePlayApiError,
  isActiveAdsRemovedSubscription,
} from '../../netlify/functions/verify-subscription.mjs';

function subscription(state, expiryTime, productId = 'ads_removed') {
  return {
    subscriptionState: state,
    lineItems: [{ productId, expiryTime }],
  };
}

const future = new Date(Date.now() + 60_000).toISOString();
const past = new Date(Date.now() - 60_000).toISOString();

test('active and grace-period subscriptions require an unexpired matching item', () => {
  assert.equal(isActiveAdsRemovedSubscription(subscription('SUBSCRIPTION_STATE_ACTIVE', future)), true);
  assert.equal(isActiveAdsRemovedSubscription(subscription('SUBSCRIPTION_STATE_IN_GRACE_PERIOD', future)), true);
  assert.equal(isActiveAdsRemovedSubscription(subscription('SUBSCRIPTION_STATE_ACTIVE', past)), false);
  assert.equal(isActiveAdsRemovedSubscription(subscription('SUBSCRIPTION_STATE_ACTIVE', future, 'other')), false);
});

test('canceled retains access until expiry, expired and invalid data do not', () => {
  assert.equal(isActiveAdsRemovedSubscription(subscription('SUBSCRIPTION_STATE_CANCELED', future)), true);
  assert.equal(isActiveAdsRemovedSubscription(subscription('SUBSCRIPTION_STATE_CANCELED', past)), false);
  assert.equal(isActiveAdsRemovedSubscription(subscription('SUBSCRIPTION_STATE_EXPIRED', future)), false);
  assert.equal(isActiveAdsRemovedSubscription(subscription('SUBSCRIPTION_STATE_ACTIVE', 'invalid')), false);
});

test('only a recognized permanent-token-invalid response classifies as inactive', () => {
  assert.equal(classifyGooglePlayFailure(new GooglePlayApiError(410, ['purchaseTokenNoLongerValid'])), 'inactive');
  assert.equal(classifyGooglePlayFailure(new GooglePlayApiError(410, ['subscriptionNoLongerAvailable'])), 'inactive');
  assert.equal(classifyGooglePlayFailure(new GooglePlayApiError(410, ['subscriptionExpired'])), 'inactive');
  assert.equal(classifyGooglePlayFailure(new GooglePlayApiError(404, ['notFound'])), 'unavailable');
  assert.equal(classifyGooglePlayFailure(new GooglePlayApiError(410)), 'unavailable');
  assert.equal(classifyGooglePlayFailure(new GooglePlayApiError(401)), 'unavailable');
  assert.equal(classifyGooglePlayFailure(new GooglePlayApiError(403)), 'unavailable');
  assert.equal(classifyGooglePlayFailure(new GooglePlayApiError(429)), 'unavailable');
  assert.equal(classifyGooglePlayFailure(new GooglePlayApiError(503)), 'unavailable');
  assert.equal(classifyGooglePlayFailure(new Error('network failure')), 'unavailable');
});
