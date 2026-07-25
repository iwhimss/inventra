const statusEl = document.getElementById('status');
const serverUrlEl = document.getElementById('serverUrl');
const pairBtn = document.getElementById('pairBtn');
const resetBtn = document.getElementById('resetBtn');

let pollTimer = null;

function setStatus(kind, text) {
  statusEl.className = kind;
  statusEl.textContent = text;
}

function normalizeUrl(url) {
  return url.trim().replace(/\/+$/, '');
}

async function loadState() {
  const { serverUrl, deviceId, apiKey } = await chrome.storage.local.get(['serverUrl', 'deviceId', 'apiKey']);
  if (serverUrl) serverUrlEl.value = serverUrl;
  if (apiKey) {
    setStatus('ok', 'Bağlandı ✓ — eklenti sunucuya eşleştirilmiş.');
  } else if (deviceId && serverUrl) {
    setStatus('pending', 'Onay bekleniyor — Inventra yönetici panelinden cihazı onaylayın.');
    startPolling(serverUrl, deviceId);
  } else {
    setStatus('none', 'Sunucuyla eşleştirilmedi.');
  }
}

async function requestHostPermission(serverUrl) {
  try {
    const origin = new URL(serverUrl).origin + '/*';
    const granted = await chrome.permissions.request({ origins: [origin] });
    return granted;
  } catch (_) {
    return false;
  }
}

function startPolling(serverUrl, deviceId) {
  if (pollTimer) clearInterval(pollTimer);
  pollTimer = setInterval(async () => {
    try {
      const resp = await fetch(`${serverUrl}/api/pair/status/${deviceId}`);
      const json = await resp.json();
      if (json.status === 'approved' && json.api_key) {
        clearInterval(pollTimer);
        await chrome.storage.local.set({ apiKey: json.api_key });
        setStatus('ok', 'Bağlandı ✓ — eklenti sunucuya eşleştirilmiş.');
      }
    } catch (_) {
      // sunucuya geçici olarak ulaşılamıyor olabilir, sessizce tekrar dene
    }
  }, 3000);
}

pairBtn.addEventListener('click', async () => {
  const serverUrl = normalizeUrl(serverUrlEl.value);
  if (!serverUrl) {
    setStatus('pending', 'Önce sunucu adresini girin.');
    return;
  }

  pairBtn.disabled = true;
  try {
    const granted = await requestHostPermission(serverUrl);
    if (!granted) {
      setStatus('pending', 'Sunucu adresine erişim izni verilmedi.');
      return;
    }

    let { deviceId } = await chrome.storage.local.get('deviceId');
    if (!deviceId) {
      deviceId = crypto.randomUUID();
    }

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
      setStatus('pending', 'Onay bekleniyor — Inventra yönetici panelinden cihazı onaylayın.');
      startPolling(serverUrl, deviceId);
    }
  } catch (e) {
    setStatus('pending', `Sunucuya bağlanılamadı: ${e}`);
  } finally {
    pairBtn.disabled = false;
  }
});

resetBtn.addEventListener('click', async () => {
  if (pollTimer) clearInterval(pollTimer);
  await chrome.storage.local.remove(['serverUrl', 'deviceId', 'apiKey']);
  serverUrlEl.value = '';
  setStatus('none', 'Sunucuyla eşleştirilmedi.');
});

loadState();
