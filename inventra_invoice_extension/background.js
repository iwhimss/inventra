// Eşleştirme onayının beklenmesi ve heartbeat gönderimi burada, arkaplan
// servisinde yapılır — popup penceresi kapansa bile (ki kullanıcı onaylamak
// için Inventra admin paneline geçtiğinde popup zaten kapanır) bu döngü
// chrome.alarms sayesinde çalışmaya devam eder.

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

// Popup açıldığında "hemen bir kontrol yap" isteği için.
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message?.type === 'inventra:check-now') {
    tick().then(() => sendResponse({ ok: true }));
    return true; // sendResponse'u async kullanmak için kanalı açık tut
  }
});

async function tick() {
  const { serverUrl, deviceId, apiKey } = await chrome.storage.local.get(['serverUrl', 'deviceId', 'apiKey']);
  if (!serverUrl || !deviceId) return;
  if (apiKey) {
    await sendHeartbeat(serverUrl, deviceId, apiKey);
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

function setBadgeConnected() {
  chrome.action.setBadgeText({ text: '✓' });
  chrome.action.setBadgeBackgroundColor({ color: '#40c057' });
}
