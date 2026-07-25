// Inventra Fatura Asistanı — içerik betiği
// turmobefatura.luca.com.tr/Invoice/Create sayfasında çalışır. Inventra'da
// hazırlanan fatura satırlarını sunucudan çeker ve sayfadaki fatura formuna
// otomatik doldurur. DOM seçicileri kullanıcının canlı sayfadan verdiği
// gerçek HTML'e dayanıyor (bkz. .plan/v0.2.3.md) ama satır indeksleme kuralı
// ve öneri listesi seçicisi tahmine dayalı — bu yüzden her satır bağımsız
// işlenir, bir satır başarısız olursa akış durmaz, sadece o satır
// "eşleşmedi" olarak işaretlenip bir sonrakine geçilir.

const ALLOWED_VAT_RATES = [0, 1, 8, 10, 18, 20];
const SUGGESTION_SELECTOR = '.Typeahead-selectable';
const SUGGESTION_WAIT_MS = 4000;
const SUGGESTION_POLL_MS = 200;
const AFTER_SELECT_WAIT_MS = 350;
const AFTER_ROW_WAIT_MS = 400;

let state = {
  running: false,
  paused: false,
  stopped: false,
  lines: [],
  results: [], // {name, status: 'pending'|'ok'|'unmatched'|'stopped'}
};

function fieldId(base, index) {
  return index === 0 ? base : `${base}${index}`;
}

function byId(id) {
  return document.getElementById(id);
}

function setNativeInputValue(el, value) {
  const setter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, 'value').set;
  setter.call(el, value);
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.dispatchEvent(new Event('change', { bubbles: true }));
}

function setSelectValueByText(selectEl, text) {
  if (!selectEl || !text) return false;
  const normalized = text.trim().toLocaleUpperCase('tr-TR');
  const options = Array.from(selectEl.options);
  const match = options.find((o) => o.text.trim().toLocaleUpperCase('tr-TR') === normalized)
    || options.find((o) => o.text.trim().toLocaleUpperCase('tr-TR').includes(normalized));
  if (!match) return false;
  selectEl.value = match.value;
  selectEl.dispatchEvent(new Event('change', { bubbles: true }));
  return true;
}

function nearestAllowedVat(vatPercent) {
  let best = ALLOWED_VAT_RATES[0];
  let bestDiff = Math.abs(vatPercent - best);
  for (const rate of ALLOWED_VAT_RATES) {
    const diff = Math.abs(vatPercent - rate);
    if (diff < bestDiff) {
      best = rate;
      bestDiff = diff;
    }
  }
  return best;
}

function formatTrNumber(value, decimals) {
  return value.toFixed(decimals).replace('.', ',');
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForPauseIfNeeded() {
  while (state.paused && !state.stopped) {
    await sleep(200);
  }
}

async function waitForSuggestions() {
  const start = Date.now();
  while (Date.now() - start < SUGGESTION_WAIT_MS) {
    const items = document.querySelectorAll(SUGGESTION_SELECTOR);
    if (items.length > 0) return Array.from(items);
    await sleep(SUGGESTION_POLL_MS);
  }
  return [];
}

function normalizeText(text) {
  return text
    .toLocaleLowerCase('tr-TR')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .trim();
}

function pickBestSuggestion(items, productName) {
  const target = normalizeText(productName);
  let best = null;
  let bestScore = -1;
  for (const item of items) {
    const text = normalizeText(item.textContent || '');
    if (!text) continue;
    let score = 0;
    if (text === target) score = 100;
    else if (text.includes(target) || target.includes(text)) score = 50;
    else {
      const targetWords = target.split(/\s+/).filter(Boolean);
      const matchedWords = targetWords.filter((w) => text.includes(w)).length;
      score = targetWords.length ? (matchedWords / targetWords.length) * 30 : 0;
    }
    if (score > bestScore) {
      bestScore = score;
      best = item;
    }
  }
  return bestScore >= 15 ? best : null;
}

async function addNewRow() {
  const btn = byId('btnAddProduct');
  if (!btn) return false;
  btn.click();
  await sleep(AFTER_ROW_WAIT_MS);
  return true;
}

async function fillRow(index, line) {
  const urunAdiEl = byId(fieldId('UrunAdi', index));
  if (!urunAdiEl) return { status: 'unmatched', reason: 'Ürün adı alanı bulunamadı (sayfa yapısı değişmiş olabilir).' };

  setNativeInputValue(urunAdiEl, line.name);
  const suggestions = await waitForSuggestions();
  if (suggestions.length === 0) {
    return { status: 'unmatched', reason: 'Ürün önerisi çıkmadı — bu sitenin kendi ürün kataloğunda bulunamamış olabilir.' };
  }

  const chosen = pickBestSuggestion(suggestions, line.name);
  if (!chosen) {
    return { status: 'unmatched', reason: 'Öneriler arasında yeterince yakın bir eşleşme bulunamadı.' };
  }

  chosen.dispatchEvent(new MouseEvent('mousedown', { bubbles: true }));
  chosen.dispatchEvent(new MouseEvent('click', { bubbles: true }));
  await sleep(AFTER_SELECT_WAIT_MS);

  const measureUnitEl = byId(fieldId('MeasureUnit', index));
  const qtyEl = byId(fieldId('Miktar', index));
  const priceEl = byId(fieldId('BirimFiyat', index));
  const discountEl = byId(fieldId('IskontoOrani', index));
  const vatEl = byId(fieldId('KDV', index));

  let warnings = [];

  if (measureUnitEl && !setSelectValueByText(measureUnitEl, line.unit)) {
    warnings.push(`birim "${line.unit}" listede bulunamadı`);
  }
  if (qtyEl) setNativeInputValue(qtyEl, formatTrNumber(line.quantity, line.quantity % 1 === 0 ? 0 : 2));
  if (priceEl) setNativeInputValue(priceEl, formatTrNumber(line.netUnitPrice, 4));
  if (discountEl) setNativeInputValue(discountEl, '0');
  if (vatEl) {
    const nearest = nearestAllowedVat(line.vatPercent);
    if (nearest !== line.vatPercent) warnings.push(`KDV %${line.vatPercent} yerine en yakın izinli değer %${nearest} kullanıldı`);
    const ok = setSelectValueByText(vatEl, String(nearest));
    if (!ok) warnings.push('KDV alanı ayarlanamadı');
  }

  return { status: 'ok', warnings };
}

async function runFill() {
  state.running = true;
  state.stopped = false;
  state.paused = false;
  state.results = state.lines.map((l) => ({ name: l.name, status: 'pending' }));
  renderPanel();

  for (let i = 0; i < state.lines.length; i++) {
    if (state.stopped) {
      for (let j = i; j < state.lines.length; j++) state.results[j].status = 'stopped';
      break;
    }
    await waitForPauseIfNeeded();
    if (state.stopped) {
      for (let j = i; j < state.lines.length; j++) state.results[j].status = 'stopped';
      break;
    }

    if (i > 0) await addNewRow();

    try {
      const result = await fillRow(i, state.lines[i]);
      state.results[i] = { name: state.lines[i].name, status: result.status, reason: result.reason, warnings: result.warnings };
    } catch (e) {
      state.results[i] = { name: state.lines[i].name, status: 'unmatched', reason: String(e) };
    }
    renderPanel();
  }

  state.running = false;
  renderPanel();
}

// ─── Panel UI ─────────────────────────────────────────────

function ensurePanel() {
  let panel = document.getElementById('inventra-panel');
  if (panel) return panel;
  panel = document.createElement('div');
  panel.id = 'inventra-panel';
  document.body.appendChild(panel);
  return panel;
}

function statusIcon(status) {
  if (status === 'ok') return '<span class="ip-ok">✓</span>';
  if (status === 'unmatched') return '<span class="ip-fail">✗</span>';
  if (status === 'stopped') return '<span class="ip-wait">⏸</span>';
  return '<span class="ip-wait">…</span>';
}

function renderPanel() {
  const panel = ensurePanel();
  const rows = state.results
    .map((r) => `<div class="ip-row-status"><span class="ip-name">${escapeHtml(r.name)}</span>${statusIcon(r.status)}</div>`)
    .join('');

  const okCount = state.results.filter((r) => r.status === 'ok').length;
  const failCount = state.results.filter((r) => r.status === 'unmatched').length;

  panel.innerHTML = `
    <div class="ip-header">
      <span>Inventra Fatura Asistanı</span>
      <span class="ip-close" id="ip-close-btn">✕</span>
    </div>
    <div class="ip-body">
      ${state.results.length === 0
        ? '<button id="ip-fetch-btn">Inventra\'dan Doldur</button>'
        : `
          ${rows}
          <div class="ip-summary">${okCount}/${state.results.length} satır dolduruldu${failCount ? `, ${failCount} satır eşleşmedi` : ''}</div>
          ${state.running
            ? `<button class="secondary" id="ip-pause-btn">${state.paused ? 'Devam Et' : 'Duraklat'}</button><button class="secondary" id="ip-stop-btn">Durdur</button>`
            : `<button id="ip-fetch-btn">Yeni Liste Çek</button>`}
        `}
    </div>
  `;

  document.getElementById('ip-close-btn')?.addEventListener('click', () => panel.remove());
  document.getElementById('ip-fetch-btn')?.addEventListener('click', fetchAndRun);
  document.getElementById('ip-pause-btn')?.addEventListener('click', () => {
    state.paused = !state.paused;
    renderPanel();
  });
  document.getElementById('ip-stop-btn')?.addEventListener('click', () => {
    state.stopped = true;
    state.paused = false;
  });
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

async function fetchAndRun() {
  const { serverUrl, apiKey } = await chrome.storage.local.get(['serverUrl', 'apiKey']);
  if (!serverUrl || !apiKey) {
    alert('Önce eklenti ayarlarından Inventra sunucusuyla eşleştirme yapmanız gerekiyor.');
    return;
  }
  try {
    const resp = await fetch(`${serverUrl}/api/invoice-export/pending`, {
      headers: { 'x-api-key': apiKey },
    });
    const json = await resp.json();
    if (!json.success || !json.data || !json.data.lines || json.data.lines.length === 0) {
      alert('Bekleyen bir fatura listesi bulunamadı. Önce Inventra\'da "Eklentiye Aktar" butonuna basın.');
      return;
    }
    state.lines = json.data.lines;
    await runFill();
  } catch (e) {
    alert(`Sunucudan liste alınamadı: ${e}`);
  }
}

ensurePanel();
renderPanel();
