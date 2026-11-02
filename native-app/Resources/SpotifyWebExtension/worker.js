const HOST = 'dev.sorayura.spotify_web';
let port, selectedTab, timer, lastAttempt = 0, polling = false;
const spotifyURL = value => { try { const u = new URL(value); return u.protocol === 'https:' && u.hostname === 'open.spotify.com'; } catch { return false; } };
function connect() {
  if (port || Date.now() - lastAttempt < 10000) return;
  lastAttempt = Date.now();
  try {
    port = chrome.runtime.connectNative(HOST);
    port.onDisconnect.addListener(() => {
      void chrome.runtime.lastError; port = null;
      chrome.action.setBadgeText({ text: selectedTab == null ? '' : '!' });
      chrome.action.setTitle({ title: 'Set up Spotify Web in Sorayura settings, then reload Spotify.' });
    });
    port.onMessage.addListener(async message => {
      if (message.type !== 'command' || selectedTab == null) return;
      try {
        const result = await chrome.tabs.sendMessage(selectedTab, message);
        if (!result?.ok) port?.postMessage({ type: 'error' });
        await poll();
      } catch { port?.postMessage({ type: 'error' }); }
    });
    chrome.action.setBadgeText({ text: '' });
    chrome.action.setTitle({ title: 'Spotify Web connected to Sorayura' });
  } catch { port = null; }
}
async function poll() {
  if (polling) return;
  polling = true;
  try {
    const tabs = await chrome.tabs.query({ url: 'https://open.spotify.com/*' });
    if (!tabs.length) {
      clearInterval(timer); timer = null; selectedTab = null;
      port?.disconnect(); port = null; return;
    }
    const candidates = (await Promise.all(tabs.map(async tab => {
      try { return { tab, snapshot: await chrome.tabs.sendMessage(tab.id, { type: 'read' }) }; }
      catch { return null; }
    }))).filter(Boolean).sort((a, b) => Number(b.snapshot.playing) - Number(a.snapshot.playing) || Number(b.tab.active) - Number(a.tab.active) || a.tab.id - b.tab.id);
    if (candidates.length) {
      selectedTab = candidates[0].tab.id;
      connect(); port?.postMessage({ type: 'snapshot', snapshot: candidates[0].snapshot });
    }
  } finally { polling = false; }
}
chrome.runtime.onMessage.addListener((message, sender) => {
  if (message.type !== 'snapshot' || !spotifyURL(sender.tab?.url)) return;
  if (!timer) timer = setInterval(poll, 2000);
  void poll();
});
chrome.tabs.onRemoved.addListener(() => { if (timer) void poll(); });
chrome.action.onClicked.addListener(async () => {
  const tabs = await chrome.tabs.query({ url: 'https://open.spotify.com/*' });
  if (tabs.length) await chrome.tabs.update(tabs[0].id, { active: true });
  else await chrome.tabs.create({ url: 'https://open.spotify.com/' });
});
