// Arkaplan servisi — bu eklentideki TÜM sunucu iletişimi burada toplanır.
// Neden: content.js sayfaya enjekte edildiği için o sayfanın kendi
// Content-Security-Policy'sine tabi olur ve çapraz-kaynak fetch() çağrıları
// engellenebilir (bu yüzden "Failed to fetch" hatası alınmıştı). Arkaplan
// servisi hiçbir sayfaya bağlı değildir, bu kısıtlamaya tabi değildir.
//
// Ayrıca eşleştirme onayının beklenmesi de burada yapılır — popup penceresi
// kapansa bile (kullanıcı onaylamak için Inventra admin paneline geçtiğinde
// popup zaten kapanır) bu döngü chrome.alarms sayesinde çalışmaya devam eder.

const ALARM_NAME = 'inventra-heartbeat';

chrome.runtime.onInstalled.addListener(() => {
  chrome.alarms.create(ALARM_NAME, { periodInMinutes: 1 });
});

chrome.runtime.onStartup.addListener(() => {
  chrome.alarms.create(ALARM_NAME, { periodInMinutes: 1 });
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === ALARM_NAME) tick();
});

chrome.notifications.onClicked.addListener(() => {
  chrome.notifications.clear('inventra-pending-export');
  try {
    chrome.action.openPopup();
  } catch (_) {
    // bazı Chromium sürümlerinde openPopup desteklenmiyor olabilir — sorun değil,
    // kullanıcı simgeye elle tıklayabilir.
  }
});

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === 'inventra:check-now') {
    tick().then(() => sendResponse({ ok: true }));
    return true;
  }
  if (message?.type === 'inventra:peek') {
    handlePeek().then(sendResponse);
    return true;
  }
  if (message?.type === 'inventra:fetch-lines') {
    handleFetchLines().then(sendResponse);
    return true;
  }
  if (message?.type === 'inventra:reject') {
    handleReject().then(sendResponse);
    return true;
  }
  return false;
});

async function getCreds() {
  return chrome.storage.local.get(['serverUrl', 'deviceId', 'apiKey']);
}

async function tick() {
  const { serverUrl, deviceId, apiKey } = await getCreds();
  if (!serverUrl || !deviceId) return;
  if (apiKey) {
    await sendHeartbeat(serverUrl, deviceId, apiKey);
    await checkForNewExportNotification(serverUrl, deviceId, apiKey);
  } else {
    await checkPairingStatus(serverUrl, deviceId);
  }
}

async function sendHeartbeat(serverUrl, deviceId, apiKey) {
  try {
    await fetch(`${serverUrl}/api/invoice-export/heartbeat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-api-key': apiKey },
      body: JSON.stringify({ device_id: deviceId }),
    });
    setBadgeConnected();
  } catch (_) {
    // sunucuya geçici olarak ulaşılamıyor — bir sonraki alarmda tekrar denenecek
  }
}

async function checkPairingStatus(serverUrl, deviceId) {
  try {
    const resp = await fetch(`${serverUrl}/api/pair/status/${deviceId}`);
    const json = await resp.json();
    if (json.status === 'approved' && json.api_key) {
      await chrome.storage.local.set({ apiKey: json.api_key });
      setBadgeConnected();
    }
  } catch (_) {
    // sunucuya geçici olarak ulaşılamıyor — bir sonraki alarmda tekrar denenecek
  }
}

// Yeni bir bekleyen fatura listesi geldiyse (daha önce bildirilmemişse)
// tarayıcı bildirimi gösterir — kullanıcı simgeye tıklamayı beklemeden
// haberdar olur.
async function checkForNewExportNotification(serverUrl, deviceId, apiKey) {
  try {
    const resp = await fetch(`${serverUrl}/api/invoice-export/peek?device_id=${encodeURIComponent(deviceId)}`, {
      headers: { 'x-api-key': apiKey },
    });
    const json = await resp.json();
    if (!json.success || !json.pending) return;

    const { notifiedCreatedAt } = await chrome.storage.local.get('notifiedCreatedAt');
    if (json.created_at === notifiedCreatedAt) return;

    await chrome.storage.local.set({ notifiedCreatedAt: json.created_at });
    chrome.notifications.create('inventra-pending-export', {
      type: 'basic',
      iconUrl: 'icons/icon128.png',
      title: 'Inventra Fatura Asistanı',
      message: `${json.sender_name || 'Inventra'} kullanıcısından ${json.line_count} ürünlük yeni bir fatura listesi geldi.`,
      priority: 1,
    });
  } catch (_) {
    // sunucuya geçici olarak ulaşılamıyor
  }
}

function setBadgeConnected() {
  chrome.action.setBadgeText({ text: '✓' });
  chrome.action.setBadgeBackgroundColor({ color: '#40c057' });
}

async function handlePeek() {
  const { serverUrl, deviceId, apiKey } = await getCreds();
  if (!serverUrl || !deviceId || !apiKey) {
    return { success: false, error: 'Eklenti henüz sunucuyla eşleştirilmemiş. Ayarlar\'dan eşleştirme yapın.' };
  }
  try {
    const resp = await fetch(`${serverUrl}/api/invoice-export/peek?device_id=${encodeURIComponent(deviceId)}`, {
      headers: { 'x-api-key': apiKey },
    });
    return await resp.json();
  } catch (e) {
    return { success: false, error: String(e) };
  }
}

async function handleFetchLines() {
  const { serverUrl, deviceId, apiKey } = await getCreds();
  if (!serverUrl || !deviceId || !apiKey) {
    return { success: false, error: 'Eklenti henüz sunucuyla eşleştirilmemiş.' };
  }
  try {
    const resp = await fetch(`${serverUrl}/api/invoice-export/pending?device_id=${encodeURIComponent(deviceId)}`, {
      headers: { 'x-api-key': apiKey },
    });
    return await resp.json();
  } catch (e) {
    return { success: false, error: String(e) };
  }
}

async function handleReject() {
  const { serverUrl, deviceId, apiKey } = await getCreds();
  if (!serverUrl || !deviceId || !apiKey) {
    return { success: false, error: 'Eklenti henüz sunucuyla eşleştirilmemiş.' };
  }
  try {
    const resp = await fetch(`${serverUrl}/api/invoice-export/reject`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-api-key': apiKey },
      body: JSON.stringify({ device_id: deviceId }),
    });
    return await resp.json();
  } catch (e) {
    return { success: false, error: String(e) };
  }
}
