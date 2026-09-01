const visitorTokenKey = 'pdf-daeri-visitor-token-v2';
const counter = document.querySelector('#visitor-count');

document.querySelector('#year')?.append(new Date().getFullYear());

if (counter) {
  loadVisitCount();
}

async function loadVisitCount() {
  try {
    const response = await fetch('/.netlify/functions/visit-count', {
      method: 'POST',
      headers: {
        Accept: 'application/json',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ visitorToken: getVisitorToken() }),
    });
    if (!response.ok) return;
    const { todayCount, totalCount } = await response.json();
    updateVisitCount('today', todayCount);
    updateVisitCount('total', totalCount);
    counter.hidden = false;
  } catch {
    // 광고 페이지의 핵심 콘텐츠는 카운터 실패와 무관하게 노출한다.
  }
}

function getVisitorToken() {
  const savedToken = localStorage.getItem(visitorTokenKey);
  if (savedToken) return savedToken;

  const visitorToken = crypto.randomUUID();
  localStorage.setItem(visitorTokenKey, visitorToken);
  return visitorToken;
}

function updateVisitCount(type, count) {
  const element = counter.querySelector(`[data-visit-count="${type}"]`);
  element.textContent = new Intl.NumberFormat('ko-KR').format(count);
}
