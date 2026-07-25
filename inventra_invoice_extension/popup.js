const contentEl = document.getElementById('content');
document.getElementById('settings-link').addEventListener('click', () => chrome.runtime.openOptionsPage());

const TARGET_URL_PATTERN = /^https:\/\/turmobefatura\.luca\.com\.tr\/Invoice\/Create/i;

let pollTimer = null;
let activeTabId = null;

function render(html) {
  contentEl.innerHTML = html;
}

async function getActiveTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  return tab;
}

async function sendToContent(message) {
  return chrome.tabs.sendMessage(activeTabId, message);
}

function statusIcon(status) {
  if (status === 'ok') return '<span class="ok">✓</span>';
  if (status === 'unmatched') return '<span class="fail">✗</span>';
  if (status === 'stopped') return '<span class="wait">⏸</span>';
  return '<span class="wait">…</span>';
}

function renderProgress(fillState) {
  if (pollTimer) clearInterval(pollTimer);
  const rows = fillState.results
    .map((r) => {
      const notes = [r.reason, ...(r.warnings || [])].filter(Boolean).join(' • ');
      const hasWarning = r.status === 'ok' && r.warnings && r.warnings.length > 0;
      return `<div class="row-status" title="${escapeHtml(notes)}"><span class="name">${escapeHtml(r.name)}</span>${hasWarning ? '<span class="wait">⚠</span>' : ''}${statusIcon(r.status)}</div>`;
    })
    .join('');
  const okCount = fillState.results.filter((r) => r.status === 'ok').length;
  const failCount = fillState.results.filter((r) => r.status === 'unmatched').length;
  const warnCount = fillState.results.filter((r) => r.status === 'ok' && r.warnings?.length).length;

  render(`
    ${rows}
    <div class="summary">${okCount}/${fillState.results.length} satır dolduruldu${warnCount ? `, ${warnCount} satırda uyarı var (üzerine gelin)` : ''}${failCount ? `, ${failCount} satır bulunamadı` : ''}</div>
    ${fillState.running
      ? `<div class="btn-row">
           <button class="secondary" id="pause-btn">${fillState.paused ? 'Devam Et' : 'Duraklat'}</button>
           <button class="danger" id="stop-btn">Durdur</button>
         </div>`
      : `<button id="recheck-btn">Yeni Liste Kontrol Et</button>`}
  `);

  document.getElementById('pause-btn')?.addEventListener('click', async () => {
    await sendToContent({ type: 'inventra:pause-toggle' });
    refreshProgress();
  });
  document.getElementById('stop-btn')?.addEventListener('click', async () => {
    await sendToContent({ type: 'inventra:stop' });
    refreshProgress();
  });
  document.getElementById('recheck-btn')?.addEventListener('click', checkPending);

  if (fillState.running) {
    pollTimer = setInterval(refreshProgress, 700);
  }
}

async function refreshProgress() {
  const resp = await sendToContent({ type: 'inventra:get-fill-state' });
  if (resp?.ok) renderProgress(resp.state);
}

function renderConfirm(peek) {
  const date = peek.created_at ? new Date(peek.created_at).toLocaleTimeString('tr-TR') : '';
  render(`
    <div class="confirm-box">
      <strong>${escapeHtml(peek.sender_name || 'Inventra')}</strong> kullanıcısından
      <strong>${peek.line_count}</strong> ürünlük bir fatura listesi geldi${date ? ` (${date})` : ''}.
      Kabul edilsin mi?
    </div>
    <div class="btn-row">
      <button id="accept-btn">Kabul Et</button>
      <button class="secondary" id="reject-btn">Reddet</button>
    </div>
  `);
  document.getElementById('accept-btn').addEventListener('click', acceptPending);
  document.getElementById('reject-btn').addEventListener('click', async () => {
    render('<p class="muted">İşleniyor...</p>');
    await chrome.runtime.sendMessage({ type: 'inventra:reject' });
    checkPending();
  });
}

async function acceptPending() {
  render('<p class="muted">Liste alınıyor...</p>');
  const resp = await chrome.runtime.sendMessage({ type: 'inventra:fetch-lines' });
  if (!resp?.success || !resp.data?.lines?.length) {
    render(`<p class="muted">Liste alınamadı: ${escapeHtml(resp?.error || 'bilinmeyen hata')}</p><button id="retry-btn">Tekrar Dene</button>`);
    document.getElementById('retry-btn')?.addEventListener('click', checkPending);
    return;
  }
  await sendToContent({ type: 'inventra:start-fill', lines: resp.data.lines });
  refreshProgress();
}

function renderIdle(error) {
  render(`
    <p class="muted">${error ? escapeHtml(error) : 'Bekleyen liste yok.'}</p>
    <button id="recheck-btn">Tekrar Kontrol Et</button>
  `);
  document.getElementById('recheck-btn').addEventListener('click', checkPending);
}

async function checkPending() {
  render('<p class="muted">Kontrol ediliyor...</p>');
  const resp = await chrome.runtime.sendMessage({ type: 'inventra:peek' });
  if (!resp?.success) {
    renderIdle(resp?.error || 'Sunucuya ulaşılamadı.');
    return;
  }
  if (resp.pending) {
    renderConfirm(resp);
  } else {
    renderIdle();
  }
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text ?? '';
  return div.innerHTML;
}

async function init() {
  const tab = await getActiveTab();
  if (!tab?.url || !TARGET_URL_PATTERN.test(tab.url)) {
    render('<p class="muted">Bu eklenti sadece turmobefatura.luca.com.tr fatura oluşturma sayfasında kullanılabilir.</p>');
    return;
  }
  activeTabId = tab.id;

  let fillState;
  try {
    const resp = await sendToContent({ type: 'inventra:get-fill-state' });
    fillState = resp?.ok ? resp.state : null;
  } catch (_) {
    render('<p class="muted">Sayfayla bağlantı kurulamadı. Sayfayı yenileyip tekrar deneyin.</p>');
    return;
  }

  if (fillState && (fillState.running || fillState.results?.length > 0)) {
    renderProgress(fillState);
  } else {
    checkPending();
  }
}

init();
