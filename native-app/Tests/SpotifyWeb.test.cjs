const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.join(__dirname, '../Resources/SpotifyWebExtension');
function player({ modern = false } = {}) {
  const clicks = [];
  const play = { disabled: false, label: 'Pause', getAttribute(k) { return k === 'aria-label' ? this.label : null; }, querySelector() { return null; }, click() { clicks.push('playpause'); this.label = this.label === 'Pause' ? 'Play' : 'Pause'; } };
  const next = { disabled: false, getAttribute() { return null; }, click() { clicks.push('next'); } };
  class Input { constructor() { this._value = '0.5'; this.max = '1'; this.events = []; } get value() { return this._value; } set value(v) { this._value = v; } dispatchEvent(event) { this.events.push(event.type); } }
  const slider = new Input();
  const document = {
    querySelector(s) {
      if (s.includes('control-button-playpause')) return play;
      if (s.includes('control-button-skip-forward')) return next;
      if (s.includes(modern ? 'context-item-link' : 'nowplaying-track-link')) return { textContent: 'Example track', getAttribute() { return modern ? '/intl-it/album/example' : '/track/0123456789ABCDEFGHIJKL'; } };
      if (modern && s.includes('now-playing-widget-v2-byline')) return { textContent: 'Example artist' };
      if (s.includes('volume-bar')) return slider;
      if (s.includes(modern ? 'cover-art-image' : 'footer img')) return { src: 'https://i.scdn.co/image/example' };
      return null;
    },
    querySelectorAll() { return modern ? [] : [{ textContent: 'Example artist' }]; }
  };
  const context = { document, HTMLInputElement: Input, Event: class { constructor(type) { this.type = type; } } };
  vm.runInNewContext(fs.readFileSync(path.join(root, 'page.js'), 'utf8'), context);
  return { page: context.SorayuraSpotifyPage, clicks, play, next, slider };
}
test('recognizes the current Spotify player even when its title links to the album', () => {
  const { page, clicks } = player({ modern: true });
  const data = page.read();
  assert.equal(data.available, true);
  assert.equal(data.trackID, 'Example track · Example artist');
  assert.equal(data.artworkURL, 'https://i.scdn.co/image/example');
  assert.equal(page.command('next track'), true);
  assert.deepEqual(clicks, ['next']);
});
test('reads only the player metadata and available controls', () => {
  const { page } = player(), data = page.read();
  assert.equal(data.title, 'Example track'); assert.equal(data.artist, 'Example artist');
  assert.equal(data.playing, true); assert.equal(data.volume, 50);
  assert.equal(data.supportedCommands.includes('next track'), true);
  assert.equal(data.supportedCommands.includes('shuffle'), false);
});
test('play and pause are idempotent and unsupported controls do nothing', () => {
  const { page, clicks } = player();
  assert.equal(page.command('play'), true); assert.deepEqual(clicks, []);
  assert.equal(page.command('pause'), true); assert.deepEqual(clicks, ['playpause']);
  page.command('pause'); assert.equal(clicks.length, 1);
  assert.equal(page.command('eval'), false); assert.equal(page.command('shuffle'), false);
});
test('volume uses input events and clamps at both ends', () => {
  const { page, slider } = player();
  for (let i=0;i<20;i++) page.command('volumeUp');
  assert.equal(Number(slider.value), 1);
  for (let i=0;i<20;i++) page.command('volumeDown');
  assert.equal(Number(slider.value), 0);
  assert.equal(slider.events.includes('input'), true); assert.equal(slider.events.includes('change'), true);
});
test('disabled Spotify controls cannot be triggered', () => {
  const { page, next, clicks } = player(); next.disabled = true;
  assert.equal(page.command('next track'), false); assert.deepEqual(clicks, []);
});
test('extension is scoped to Spotify and has no external website messaging', () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json')));
  assert.deepEqual(manifest.permissions, ['nativeMessaging']);
  assert.deepEqual(manifest.host_permissions, ['https://open.spotify.com/*']);
  assert.deepEqual(manifest.content_scripts[0].matches, manifest.host_permissions);
  assert.equal(manifest.externally_connectable, undefined);
  const digest = require('node:crypto').createHash('sha256').update(Buffer.from(manifest.key, 'base64')).digest('hex').slice(0,32);
  assert.equal([...digest].map(x => String.fromCharCode(97+parseInt(x,16))).join(''), 'lfejofhcidmggplkmaccdbokjonncdek');
});
test('content script stops observing when Chrome invalidates its runtime', async () => {
  let mutation, publish, disconnected = false, sends = 0;
  const context = {
    chrome: { runtime: { id: 'test', onMessage: { addListener() {} }, sendMessage() {
      if (++sends > 1) throw new Error('Extension context invalidated.');
      return Promise.resolve();
    } } },
    document: { body: {} },
    MutationObserver: class {
      constructor(callback) { mutation = callback; }
      observe() {}
      disconnect() { disconnected = true; }
    },
    SorayuraSpotifyPage: { read() { return {}; } },
    setTimeout(callback) { publish = callback; return 1; },
    clearTimeout() {}
  };
  vm.runInNewContext(fs.readFileSync(path.join(root, 'content.js'), 'utf8'), context);
  mutation();
  await publish();
  assert.equal(disconnected, true);
  mutation();
  await publish();
  assert.equal(sends, 2);
});
test('worker rejects other origins, routes controls to the Spotify tab, and disconnects after closure', async () => {
  const posted = [], sent = []; let listener, commandListener, connections = 0, disconnected = false;
  let tabs = [{ id: 9, active: true, url: 'https://open.spotify.com/' }];
  const port = { onDisconnect: { addListener() {} }, onMessage: { addListener(fn) { commandListener=fn; } }, postMessage(message) { posted.push(message); }, disconnect() { disconnected=true; } };
  const chrome = {
    runtime: { onMessage: { addListener(fn) { listener=fn; } }, connectNative() { connections++; return port; } },
    tabs: { async query() { return tabs; }, async sendMessage(id,message) { sent.push([id,message]); return message.type === 'read' ? { playing: true, title: 'Track' } : { ok: true }; }, onRemoved: { addListener() {} } },
    action: { setBadgeText() {}, setTitle() {}, onClicked: { addListener() {} } }
  };
  const context = vm.createContext({ chrome, URL, Date, setInterval() { return 1; }, clearInterval() {} });
  vm.runInContext(fs.readFileSync(path.join(root, 'worker.js'), 'utf8'), context);
  listener({ type:'snapshot' }, { tab: { url:'https://evil.test/' } });
  assert.equal(connections,0);
  listener({ type:'snapshot' }, { tab:tabs[0] });
  await new Promise(setImmediate);
  assert.equal(connections,1); assert.equal(posted[0].snapshot.title,'Track');
  await commandListener({ type:'command',action:'pause' });
  assert.equal(sent.some(([id,m]) => id===9 && m.action==='pause'),true);
  tabs=[]; await vm.runInContext('poll()',context);
  assert.equal(disconnected,true);
});
test('store icons are packaged at the declared dimensions with transparent padding', () => {
  const manifest = JSON.parse(fs.readFileSync(path.join(root, 'manifest.json')));
  assert.ok(manifest.description.length <= 132);
  assert.deepEqual(Object.keys(manifest.icons), ['16', '32', '48', '128']);
  assert.deepEqual(manifest.action.default_icon, manifest.icons);
  for (const [size, name] of Object.entries(manifest.icons)) {
    const png = fs.readFileSync(path.join(root, name));
    assert.equal(png.subarray(1,4).toString(), 'PNG');
    assert.equal(png.readUInt32BE(16), Number(size));
    assert.equal(png.readUInt32BE(20), Number(size));
    assert.equal(png[25], 6); // RGBA, rather than an opaque image on a false margin.
  }
});
