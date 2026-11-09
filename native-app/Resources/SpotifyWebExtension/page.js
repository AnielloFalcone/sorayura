// Runs in Chrome's isolated content-script world, only on open.spotify.com.
globalThis.SorayuraSpotifyPage = (() => {
  const selectors = {
    playpause: '[data-testid="control-button-playpause"], [data-testid="play-pause-button"]',
    'previous track': '[data-testid="control-button-skip-back"]',
    'next track': '[data-testid="control-button-skip-forward"]',
    shuffle: '[data-testid="control-button-shuffle"]',
    repeat: '[data-testid="control-button-repeat"]'
  };
  const get = (selector) => document.querySelector(selector);
  const widget = '[data-testid="now-playing-widget-v2"]';
  const volume = () => get('[data-testid="volume-bar"] input[type="range"], input[aria-label="Volume"]');
  const enabled = (element) => element && !element.disabled && element.getAttribute('aria-disabled') !== 'true';
  function read() {
    const play = get(selectors.playpause);
    const title = get(`${widget} [data-testid="context-item-link"], [data-testid="nowplaying-track-link"], [data-testid="context-item-info-title"]`);
    const byline = get(`${widget} [data-testid="now-playing-widget-v2-byline"]`);
    const artists = byline?.textContent.trim() || [...document.querySelectorAll('[data-testid="context-item-info-artist"]')]
      .map(n => n.textContent.trim()).filter(Boolean).join(', ');
    const track = (title?.textContent || '').trim();
    const link = title?.getAttribute('href') || '';
    const slider = volume();
    const supportedCommands = Object.keys(selectors).filter(action => enabled(get(selectors[action])));
    if (enabled(play)) supportedCommands.push('play', 'pause');
    if (slider) supportedCommands.push('volumeUp', 'volumeDown');
    const label = play?.getAttribute('aria-label') || '';
    const playing = /pause|pausa/i.test(label) || !!play?.querySelector('[data-icon="pause"]');
    return {
      title: track.slice(0, 512),
      artist: artists.slice(0, 512), album: '',
      available: !!track && !!play, playing,
      artworkURL: get(`${widget} img[data-testid="cover-art-image"], footer img[src*="scdn.co"]`)?.src || '',
      trackID: (/\/(track|episode)\//.test(link) ? link : `${track} · ${artists}`).slice(0, 160),
      volume: slider ? Math.round(Number(slider.value) / (Number(slider.max) || 1) * 100) : 50,
      shuffle: get(selectors.shuffle)?.getAttribute('aria-checked') === 'true',
      repeatEnabled: ['true', 'mixed'].includes(get(selectors.repeat)?.getAttribute('aria-checked')),
      supportedCommands
    };
  }
  function command(action) {
    const state = read();
    if (!state.supportedCommands.includes(action)) return false;
    if ((action === 'play' && state.playing) || (action === 'pause' && !state.playing)) return true;
    if (action === 'volumeUp' || action === 'volumeDown') {
      const slider = volume(), maximum = Number(slider.max) || 1;
      const next = Math.min(maximum, Math.max(0, Number(slider.value) + (action === 'volumeUp' ? 0.1 : -0.1) * maximum));
      // Use the platform setter so Spotify's controlled input receives the change.
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(slider, String(next));
      slider.dispatchEvent(new Event('input', { bubbles: true }));
      slider.dispatchEvent(new Event('change', { bubbles: true }));
      return true;
    }
    const target = get(selectors[action === 'play' || action === 'pause' ? 'playpause' : action]);
    if (!enabled(target)) return false;
    target.click(); return true;
  }
  return { read, command };
})();
