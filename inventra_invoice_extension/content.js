// Inventra Fatura Asistanı — içerik betiği
// turmobefatura.luca.com.tr/Invoice/Create sayfasında çalışır. Sadece DOM
// doldurma mantığını içerir — sunucuyla konuşmaz (bu sayfanın kendi
// Content-Security-Policy'si content script'ten yapılan çapraz-kaynak
// fetch() çağrılarını engelliyor, bu yüzden tüm ağ isteği background.js'te
// toplandı). Popup, mesajlarla bu betiğe "şu satırları doldur" der, bu
// betik ilerlemesini yine mesajlarla popup'a bildirir.
//
// Not: Ürün Adı alanı sitenin bir "typeahead" (otomatik tamamlama) kutusu
// olsa da, bu sadece kullanıcının o sitede kayıtlı bir ürün kataloğu varsa
// devreye giriyor. Kataloğa bağlı değilseniz (yaygın kullanım) ürün adı da
// tıpkı Miktar/Birim Fiyat gibi serbest metin olarak yazılır — hiçbir öneri
// listesi beklenmez veya tıklanmaz.

const ALLOWED_VAT_RATES = [0, 1, 8, 10, 18, 20];
const AFTER_FIELD_WAIT_MS = 150;
const AFTER_ROW_WAIT_MS = 400;

let state = {
  running: false,
  paused: false,
  stopped: false,
  lines: [],
  results: [], // {name, status: 'pending'|'ok'|'unmatched'|'stopped', warnings?: string[]}
};

function log(...args) {
  console.log('[Inventra]', ...args);
}

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

async function addNewRow() {
  const btn = byId('btnAddProduct');
  if (!btn) {
    log('"Yeni Satır Ekle" butonu (#btnAddProduct) bulunamadı.');
    return false;
  }
  btn.click();
  await sleep(AFTER_ROW_WAIT_MS);
  return true;
}

// Ürün Adı dahil TÜM alanları doğrudan, serbest metin olarak doldurur —
// hiçbir öneri listesi beklenmez/tıklanmaz. Birim ve KDV birer <select>
// olduğu için metin eşleşmesiyle seçilir, diğerleri düz metin girişidir.
async function fillRow(index, line) {
  log(`Satır ${index}: "${line.name}" dolduruluyor...`);

  const urunAdiEl = byId(fieldId('UrunAdi', index));
  if (!urunAdiEl) {
    log(`Satır ${index}: Ürün Adı alanı (#${fieldId('UrunAdi', index)}) bulunamadı — satır indeksleme varsayımı bu sayfada geçerli olmayabilir.`);
    return { status: 'unmatched', reason: `Ürün adı alanı (#${fieldId('UrunAdi', index)}) bulunamadı.` };
  }

  const warnings = [];
  setNativeInputValue(urunAdiEl, line.name);
  await sleep(AFTER_FIELD_WAIT_MS);

  const measureUnitEl = byId(fieldId('MeasureUnit', index));
  if (measureUnitEl) {
    const ok = setSelectValueByText(measureUnitEl, line.unit);
    log(`Satır ${index}: Birim "${line.unit}" ${ok ? 'seçildi' : 'BULUNAMADI'}.`);
    if (!ok) warnings.push(`birim "${line.unit}" listede bulunamadı`);
  } else {
    log(`Satır ${index}: Birim alanı (#${fieldId('MeasureUnit', index)}) bulunamadı.`);
    warnings.push('Birim alanı bulunamadı');
  }

  const qtyEl = byId(fieldId('Miktar', index));
  if (qtyEl) {
    setNativeInputValue(qtyEl, formatTrNumber(line.quantity, line.quantity % 1 === 0 ? 0 : 2));
  } else {
    log(`Satır ${index}: Miktar alanı (#${fieldId('Miktar', index)}) bulunamadı.`);
    warnings.push('Miktar alanı bulunamadı');
  }

  const priceEl = byId(fieldId('BirimFiyat', index));
  if (priceEl) {
    setNativeInputValue(priceEl, formatTrNumber(line.netUnitPrice, 4));
  } else {
    log(`Satır ${index}: Birim Fiyat alanı (#${fieldId('BirimFiyat', index)}) bulunamadı.`);
    warnings.push('Birim fiyat alanı bulunamadı');
  }

  const discountEl = byId(fieldId('IskontoOrani', index));
  if (discountEl) setNativeInputValue(discountEl, '0');

  const vatEl = byId(fieldId('KDV', index));
  if (vatEl) {
    const nearest = nearestAllowedVat(line.vatPercent);
    if (nearest !== line.vatPercent) warnings.push(`KDV %${line.vatPercent} yerine en yakın izinli değer %${nearest} kullanıldı`);
    const ok = setSelectValueByText(vatEl, String(nearest));
    log(`Satır ${index}: KDV %${nearest} ${ok ? 'seçildi' : 'BULUNAMADI'}.`);
    if (!ok) warnings.push('KDV alanı ayarlanamadı');
  } else {
    log(`Satır ${index}: KDV alanı (#${fieldId('KDV', index)}) bulunamadı.`);
    warnings.push('KDV alanı bulunamadı');
  }

  log(`Satır ${index}: tamamlandı.`, warnings.length ? { warnings } : '(uyarı yok)');
  return { status: 'ok', warnings };
}

async function runFill(lines) {
  state.running = true;
  state.stopped = false;
  state.paused = false;
  state.lines = lines;
  state.results = lines.map((l) => ({ name: l.name, status: 'pending' }));
  log(`Doldurma başlıyor — ${lines.length} satır.`);

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
      log(`Satır ${i}: beklenmeyen hata`, e);
      state.results[i] = { name: state.lines[i].name, status: 'unmatched', reason: String(e) };
    }
  }

  log('Doldurma bitti.', state.results);
  state.running = false;
}

// ─── Popup ile mesajlaşma ─────────────────────────────────

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === 'inventra:start-fill') {
    runFill(message.lines || []);
    sendResponse({ ok: true });
    return false;
  }
  if (message?.type === 'inventra:pause-toggle') {
    state.paused = !state.paused;
    sendResponse({ ok: true, paused: state.paused });
    return false;
  }
  if (message?.type === 'inventra:stop') {
    state.stopped = true;
    state.paused = false;
    sendResponse({ ok: true });
    return false;
  }
  if (message?.type === 'inventra:get-fill-state') {
    sendResponse({ ok: true, state });
    return false;
  }
  return false;
});
