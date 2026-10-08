const visitorTokenPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

export function isValidVisitorToken(visitorToken) {
  return typeof visitorToken === 'string' && visitorTokenPattern.test(visitorToken);
}
