const visitFlagKey = 'pdf-daeri-visit-recorded-v1';
const counter = document.querySelector('#visitor-count');

document.querySelector('#year')?.append(new Date().getFullYear());

if (counter) {
  loadVisitCount();
}

async function loadVisitCount() {
  const firstVisit = localStorage.getItem(visitFlagKey) !== 'true';
  try {
    const response = await fetch('/.netlify/functions/visit-count', {
      method: firstVisit ? 'POST' : 'GET',
      headers: { Accept: 'application/json' },
    });
    if (!response.ok) return;
    const { count } = await response.json();
    if (firstVisit) localStorage.setItem(visitFlagKey, 'true');
    const value = counter.querySelector('strong');
    value.textContent = new Intl.NumberFormat('ko-KR').format(count);
    counter.hidden = false;
  } catch {
    // 광고 페이지의 핵심 콘텐츠는 카운터 실패와 무관하게 노출한다.
  }
}
