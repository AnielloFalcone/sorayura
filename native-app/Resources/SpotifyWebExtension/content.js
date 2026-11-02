(() => {
  let pending;
  const publish = () => {
    clearTimeout(pending); pending = null;
    chrome.runtime.sendMessage({ type: 'snapshot', snapshot: SorayuraSpotifyPage.read() }).catch(() => {});
  };
  chrome.runtime.onMessage.addListener((message, sender, reply) => {
    if (message.type === 'read') reply(SorayuraSpotifyPage.read());
    else if (message.type === 'command') {
      reply({ ok: SorayuraSpotifyPage.command(message.action) });
      setTimeout(publish, 100);
    }
  });
  new MutationObserver(() => {
    if (!pending) pending = setTimeout(publish, 150);
  }).observe(document.body, { subtree: true, childList: true, attributes: true, characterData: true });
  publish();
})();
