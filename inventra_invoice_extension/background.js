const ALARM_NAME = 'inventra-heartbeat';

chrome.runtime.onInstalled.addListener(() => {
  chrome.alarms.create(ALARM_NAME, { periodInMinutes: 1 });
});

chrome.runtime.onStartup.addListener(() => {
  chrome.alarms.create(ALARM_NAME, { periodInMinutes: 1 });
});

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === ALARM_NAME) sendHeartbeat();
});

async function sendHeartbeat() {
  const { serverUrl, deviceId, apiKey } = await chrome.storage.local.get(['serverUrl', 'deviceId', 'apiKey']);
  if (!serverUrl || !deviceId || !apiKey) return;
  try {
    await fetch(`${serverUrl}/api/invoice-export/heartbeat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-api-key': apiKey },
      body: JSON.stringify({ device_id: deviceId }),
    });
  } catch (_) {
    // sunucuya geçici olarak ulaşılamıyor — bir sonraki alarmda tekrar denenecek
  }
}
