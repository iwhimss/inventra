const statusEl = document.getElementById('status');
const serverUrlEl = document.getElementById('serverUrl');
const pairBtn = document.getElementById('pairBtn');
const resetBtn = document.getElementById('resetBtn');

function setStatus(kind, text) {
  statusEl.className = kind;
  statusEl.textContent = text;
}

function normalizeUrl(url) {
  return url.trim().replace(/\/+$/, '');
}

function hasValidProtocol(url) {
  return /^https?:\/\//i.test(url);
}

async function loadState() {
  const { serverUrl, deviceId, apiKey } = await chrome.storage.local.get(['serverUrl', 'deviceId', 'apiKey']);
  if (serverUrl) serverUrlEl.value = serverUrl;

  if (apiKey) {
    setStatus('ok', 'Bağlandı ✓ — eklenti sunucuya eşleştirilmiş.');
    return;
  }

  if (deviceId && serverUrl) {
    setStatus(
      'pending',
      'Onay bekleniyor — Inventra yönetici panelinden cihazı onaylayın. Bu pencereyi kapatabilirsiniz, arkaplanda otomatik kontrol ediliyor (en geç ~1 dakika içinde bağlanır).',
    );
    // Popup açılır açılmaz taze bir kontrol iste — arkaplan alarmının bir
    // sonraki tetiklenmesini beklemek yerine anında sonucu görebilmek için.
    chrome.runtime.sendMessage({ type: 'inventra:check-now' }, async () => {
      const fresh = await chrome.storage.local.get('apiKey');
      if (fresh.apiKey) setStatus('ok', 'Bağlandı ✓ — eklenti sunucuya eşleştirilmiş.');
    });
    return;
  }

  setStatus('none', 'Sunucuyla eşleştirilmedi.');
}

async function requestHostPermission(serverUrl) {
  try {
    const origin = new URL(serverUrl).origin + '/*';
    const granted = await chrome.permissions.request({ origins: [origin] });
    return { granted };
  } catch (e) {
    return { granted: false, error: String(e) };
  }
}

pairBtn.addEventListener('click', async () => {
  const serverUrl = normalizeUrl(serverUrlEl.value);
  if (!serverUrl) {
    setStatus('pending', 'Önce sunucu adresini girin.');
    return;
  }
  if (!hasValidProtocol(serverUrl)) {
    setStatus(
      'pending',
      "Adresin başına http:// veya https:// eklemeniz gerekiyor (VDS/domain için genelde https://, yerel ağ IP'si için genelde http://).",
    );
    return;
  }

  pairBtn.disabled = true;
  try {
    const { granted, error } = await requestHostPermission(serverUrl);
    if (!granted) {
      setStatus(
        'pending',
        error
          ? `İzin isteği başarısız: ${error}`
          : 'Tarayıcı erişim izni vermedi. Adresin doğru yazıldığından emin olup tekrar deneyin.',
      );
      return;
    }

    let { deviceId } = await chrome.storage.local.get('deviceId');
    if (!deviceId) deviceId = crypto.randomUUID();

    const resp = await fetch(`${serverUrl}/api/pair/request`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        device_id: deviceId,
        device_name: 'Fatura Eklentisi (Tarayıcı)',
        device_type: 'browser_extension',
      }),
    });
    const json = await resp.json();

    await chrome.storage.local.set({ serverUrl, deviceId });

    if (json.status === 'approved' && json.api_key) {
      await chrome.storage.local.set({ apiKey: json.api_key });
      setStatus('ok', 'Bağlandı ✓ — eklenti sunucuya eşleştirilmiş.');
    } else {
      setStatus(
        'pending',
        'Onay bekleniyor — Inventra yönetici panelinden cihazı onaylayın. Bu pencereyi kapatabilirsiniz, arkaplanda otomatik kontrol edilecek.',
      );
    }
  } catch (e) {
    setStatus('pending', `Sunucuya bağlanılamadı: ${e}`);
  } finally {
    pairBtn.disabled = false;
  }
});

resetBtn.addEventListener('click', async () => {
  await chrome.storage.local.remove(['serverUrl', 'deviceId', 'apiKey']);
  serverUrlEl.value = '';
  chrome.action.setBadgeText({ text: '' });
  setStatus('none', 'Sunucuyla eşleştirilmedi.');
});

loadState();
