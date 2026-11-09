(() => {
  let pending;
  let stopped = false;
  const stop = () => {
    stopped = true;
    clearTimeout(pending); pending = null;
    observer.disconnect();
  };
  const publish = async () => {
    clearTimeout(pending); pending = null;
    if (stopped) return;
    if (!chrome.runtime?.id) { stop(); return; }
    const snapshot = SorayuraSpotifyPage.read();
    try {
      await chrome.runtime.sendMessage({ type: 'snapshot', snapshot });
    } catch (error) {
      if (!chrome.runtime?.id || /extension context invalidated/i.test(error?.message ?? '')) stop();
    }
  };
  chrome.runtime.onMessage.addListener((message, sender, reply) => {
    if (message.type === 'read') reply(SorayuraSpotifyPage.read());
    else if (message.type === 'command') {
      reply({ ok: SorayuraSpotifyPage.command(message.action) });
      setTimeout(publish, 100);
    }
  });
  const observer = new MutationObserver(() => {
    if (!stopped && !pending) pending = setTimeout(publish, 150);
  });
  observer.observe(document.body, { subtree: true, childList: true, attributes: true, characterData: true });
  publish();
})();
