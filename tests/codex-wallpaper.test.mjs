import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import crypto from 'node:crypto';
import vm from 'node:vm';
import { run } from '../runtime/codex-wallpaper.mjs';

if (!process.env.GPTPET_TEST_ROOT) throw new Error('Use scripts/run-tests.mjs to isolate generated data.');
const outputRoot = path.resolve(process.env.GPTPET_TEST_ROOT, 'wallpaper');
fs.mkdirSync(outputRoot, { recursive: true });
const dataDir = fs.mkdtempSync(path.join(outputRoot, 'wallpaper-'));
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRbkAAAAASUVORK5CYII=', 'base64');
const image = path.join(dataDir, 'sample.png');
fs.writeFileSync(image, png);

function fakeRenderer(dreamSkinActive = false) {
  const nodes = new Map();
  const attributes = new Map();
  const document = {
    body: {},
    head: { appendChild(node) { nodes.set(node.id, node); node.remove = () => nodes.delete(node.id); } },
    documentElement: {
      setAttribute(name, value) { attributes.set(name, value); },
      getAttribute(name) { return attributes.get(name) ?? null; },
      hasAttribute(name) { return attributes.has(name); },
      removeAttribute(name) { attributes.delete(name); },
    },
    getElementById(id) { return id === 'root' ? {} : nodes.get(id) ?? null; },
    querySelector() { return null; },
    createElement() { return { id: '', textContent: '' }; },
  };
  return { nodes, attributes, context: { document, window: dreamSkinActive ? { __CODEX_DREAM_SKIN_STATE__: {} } : {} } };
}

const mockSockets = new WeakMap();
async function closeCdp(server) {
  // Upgraded sockets are not closed by http.Server.close(), especially when
  // simulating a peer that disconnects without a WebSocket close handshake.
  for (const socket of mockSockets.get(server) ?? []) socket.destroy();
  await new Promise(resolve => server.close(resolve));
}

async function mockCdp(pageUrl = 'app://codex/home', dreamSkinActive = false, { pages = 1, disconnect = false, unresponsive = false, failedPages = [] } = {}) {
  const renderer = fakeRenderer(dreamSkinActive);
  const server = http.createServer((request, response) => {
    const port = server.address().port;
    response.setHeader('Content-Type', 'application/json');
    if (request.url === '/json/version') response.end(JSON.stringify({ webSocketDebuggerUrl: `ws://127.0.0.1:${port}/devtools/browser/test-browser` }));
    else if (request.url === '/json/list') response.end(JSON.stringify(Array.from({ length: pages }, (_, index) => ({
      type: 'page', id: `test-page-${index}`, url: pageUrl,
      webSocketDebuggerUrl: `ws://127.0.0.1:${port}/devtools/page/test-page-${index}`,
    }))));
    else { response.statusCode = 404; response.end('{}'); }
  });
  const sockets = new Set();
  mockSockets.set(server, sockets);
  server.on('connection', socket => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
    socket.on('error', () => {});
  });
  server.on('upgrade', (request, socket) => {
    const accept = crypto.createHash('sha1').update(request.headers['sec-websocket-key'] + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
    socket.write(`HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: ${accept}\r\n\r\n`);
    let pending = Buffer.alloc(0);
    socket.on('data', chunk => {
      pending = Buffer.concat([pending, chunk]);
      if (pending.length < 6) return;
      let length = pending[1] & 0x7f;
      let offset = 2;
      if (length === 126) { if (pending.length < 8) return; length = pending.readUInt16BE(2); offset = 4; }
      if (length === 127) { if (pending.length < 14) return; length = Number(pending.readBigUInt64BE(2)); offset = 10; }
      if (pending.length < offset + 4 + length) return;
      if ((pending[0] & 0x0f) !== 1) { socket.end(); pending = Buffer.alloc(0); return; }
      const mask = pending.subarray(offset, offset + 4);
      const payload = Buffer.from(pending.subarray(offset + 4, offset + 4 + length));
      for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i % 4];
      const message = JSON.parse(payload.toString('utf8'));
      if (disconnect) { socket.end(Buffer.from([0x88, 0])); return; }
      if (unresponsive) { pending = Buffer.alloc(0); return; }
      let result;
      try { result = vm.runInNewContext(message.params.expression, renderer.context); }
      catch (error) { result = false; }
      const failed = failedPages.some(index => request.url.endsWith(`/test-page-${index}`));
      const body = Buffer.from(JSON.stringify(failed ? { id: message.id, error: { code: -32000 } } : { id: message.id, result: { result: { type: 'boolean', value: result } } }));
      socket.write(Buffer.concat([Buffer.from([0x81, body.length]), body]), () => socket.end());
      pending = Buffer.alloc(0);
    });
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return { server, port: server.address().port, renderer };
}

test('wallpaper import, opt-in, CDP application and restoration stay in isolated data', async () => {
  assert.equal((await run('status', dataDir)).enabled, false);
  assert.equal((await run('status', dataDir)).dimming, 60);
  await assert.rejects(run('apply', dataDir), /启用/);
  const invalid = path.join(dataDir, 'invalid.png');
  fs.writeFileSync(invalid, 'not an image');
  await assert.rejects(run('import', dataDir, invalid), /图片无效/);
  const truncated = path.join(dataDir, 'truncated.png');
  fs.writeFileSync(truncated, png.subarray(0, 24));
  await assert.rejects(run('import', dataDir, truncated), /PNG 图片不完整/);
  assert.equal((await run('status', dataDir)).selected, null);
  const imported = await run('import', dataDir, image);
  assert.equal(imported.width, 1);
  assert.equal(imported.height, 1);
  assert.equal(fs.existsSync(path.join(dataDir, 'codex-wallpaper', 'images', imported.selected)), true);
  const { server, port, renderer } = await mockCdp();
  try {
    await run('enable', dataDir);
    assert.equal((await run('apply', dataDir, undefined, { port })).applied, true);
    assert.equal(renderer.nodes.has('gpt-niang-codex-wallpaper-style'), true);
    assert.match(renderer.nodes.get('gpt-niang-codex-wallpaper-style').textContent, /background-image: linear-gradient\(rgba\(14, 15, 20, 0\.60\), rgba\(14, 15, 20, 0\.60\)\), url\(/);
    assert.match(renderer.nodes.get('gpt-niang-codex-wallpaper-style').textContent, /\[data-app-shell-main-surface\], html\[data-gpt-niang-codex-wallpaper="on"\] \[data-sidebar-navigation-root\] \{ background: transparent !important; \}/);
    assert.match(renderer.nodes.get('gpt-niang-codex-wallpaper-style').textContent, /\[data-app-shell-main-content-top-fade\] > \[class\*="_MainContentTopFade_"\] \{ background: transparent !important; \}/);
    assert.match(renderer.nodes.get('gpt-niang-codex-wallpaper-style').textContent, /\[data-app-action-timeline-scroll\] \[aria-hidden="true"\]\[class~="pointer-events-none"\]\[class~="bottom-0"\]\[class~="bg-surface"\]/);
    assert.match(renderer.nodes.get('gpt-niang-codex-wallpaper-style').textContent, /\[class~="from-surface"\] \{ background: transparent !important; \}/);
    await assert.rejects(run('set-dimming', dataDir, '100', { port }), /明暗值无效/);
    assert.equal((await run('set-dimming', dataDir, '75', { port })).dimming, 75);
    assert.equal((await run('status', dataDir)).dimming, 75);
    assert.match(renderer.nodes.get('gpt-niang-codex-wallpaper-style').textContent, /rgba\(14, 15, 20, 0\.75\)/);
    assert.equal(renderer.attributes.get('data-gpt-niang-codex-wallpaper'), 'on');
    assert.equal((await run('restore', dataDir, undefined, { port })).restored, true);
    assert.equal(renderer.nodes.has('gpt-niang-codex-wallpaper-style'), false);
    assert.equal(renderer.attributes.has('data-gpt-niang-codex-wallpaper'), false);
    assert.equal((await run('disable', dataDir, undefined, { port })).enabled, false);
  } finally { await closeCdp(server); }
});

test('a different app on the same debug port is never modified', async () => {
  const { server, port, renderer } = await mockCdp('app://other-app/home');
  try {
    await run('enable', dataDir);
    await assert.rejects(run('apply', dataDir, undefined, { port }), /没有找到 Codex 页面/);
    assert.equal(renderer.nodes.size, 0);
  } finally {
    await closeCdp(server);
    await run('disable', dataDir, undefined, { port });
  }
});

test('current Codex route works and active Dream Skin remains untouched', async () => {
  const { server, port, renderer } = await mockCdp('app://-/index.html', true);
  try {
    await run('enable', dataDir);
    await assert.rejects(run('apply', dataDir, undefined, { port }), /Dream Skin 正在使用中/);
    assert.equal(renderer.nodes.size, 0);
    assert.equal((await run('restore', dataDir, undefined, { port })).restored, true);
  } finally {
    await closeCdp(server);
    await run('disable', dataDir, undefined, { port });
  }
});

test('avatar overlay is never selected as the wallpaper page', async () => {
  const { server, port, renderer } = await mockCdp('app://-/index.html?initialRoute=%2Favatar-overlay');
  try {
    await run('enable', dataDir);
    await assert.rejects(run('apply', dataDir, undefined, { port }), /没有找到 Codex 页面/);
    assert.equal(renderer.nodes.size, 0);
  } finally {
    await closeCdp(server);
    await run('disable', dataDir, undefined, { port });
  }
});

test('a disconnected page fails immediately instead of waiting for the response timeout', async () => {
  const { server, port } = await mockCdp(undefined, false, { disconnect: true });
  try {
    await run('enable', dataDir);
    const started = performance.now();
    await assert.rejects(run('apply', dataDir, undefined, { port }), /连接已断开/);
    assert.ok(performance.now() - started < 2000);
  } finally { await closeCdp(server); }
});

test('multiple unresponsive pages share a bounded parallel wait', async () => {
  const { server, port } = await mockCdp(undefined, false, { pages: 4, unresponsive: true });
  try {
    const started = performance.now();
    await assert.rejects(run('apply', dataDir, undefined, { port }), /未响应/);
    assert.ok(performance.now() - started < 7500, 'Four page timeouts must not accumulate sequentially.');
  } finally { await closeCdp(server); }
});

test('partial application and disable report windows that did not restore', async () => {
  const { server, port } = await mockCdp(undefined, false, { pages: 2, failedPages: [1] });
  try {
    const result = await run('apply', dataDir, undefined, { port });
    assert.equal(result.pages, 1);
    assert.equal(result.totalPages, 2);
    assert.match(result.warning, /1 个页面未完成/);
    const disabled = await run('disable', dataDir, undefined, { port });
    assert.equal(disabled.enabled, false);
    assert.equal(disabled.restored, false);
    assert.match(disabled.warning, /1 个页面未完成/);
  } finally { await closeCdp(server); }
});

function pngWithComment(value) {
  const data = Buffer.from('Comment\0' + value);
  const type = Buffer.from('tEXt');
  let crc = 0xffffffff;
  for (const byte of Buffer.concat([type, data])) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  const chunk = Buffer.alloc(data.length + 12);
  chunk.writeUInt32BE(data.length); type.copy(chunk, 4); data.copy(chunk, 8);
  chunk.writeUInt32BE((crc ^ 0xffffffff) >>> 0, chunk.length - 4);
  return Buffer.concat([png.subarray(0, -12), chunk, png.subarray(-12)]);
}

async function selectionFixture() {
  const dir = fs.mkdtempSync(path.join(outputRoot, 'selection-'));
  const firstBytes = pngWithComment('first'), secondBytes = pngWithComment('second');
  const firstFile = path.join(dir, 'first.png'), secondFile = path.join(dir, 'second.png');
  fs.writeFileSync(firstFile, firstBytes); fs.writeFileSync(secondFile, secondBytes);
  const first = await run('import', dir, firstFile), second = await run('import', dir, secondFile);
  return { dir, first, second, firstBytes };
}

test('select an older imported wallpaper while disabled without enabling or losing other images', async () => {
  const { dir, first, second } = await selectionFixture();
  await run('set-dimming', dir, '75');
  assert.equal((await run('status', dir)).selected, second.selected);
  const selected = await run('select', dir, first.selected);
  assert.equal(selected.selected, first.selected);
  assert.equal(selected.enabled, false); assert.equal(selected.applied, false);
  assert.equal(selected.warning, undefined);
  assert.equal((await run('status', dir)).dimming, 75);
  assert.deepEqual(fs.readdirSync(path.join(dir, 'codex-wallpaper', 'images')).sort(), [first.selected, second.selected].sort());
});

test('selecting with wallpaper enabled applies the selected bytes and preserves dimming', async () => {
  const { dir, first, firstBytes } = await selectionFixture();
  const { server, port, renderer } = await mockCdp();
  const readFile = fs.readFileSync;
  try {
    await run('enable', dir);
    await run('set-dimming', dir, '75', { port });
    const selectedPath = path.join(dir, 'codex-wallpaper', 'images', first.selected);
    let imageReads = 0;
    fs.readFileSync = function(file, ...args) {
      if (file === selectedPath) imageReads++;
      return readFile.call(this, file, ...args);
    };
    const result = await run('select', dir, first.selected, { port });
    assert.equal(imageReads, 1, 'Selection must reuse its validated image instead of reading it again for application.');
    assert.equal(result.applied, true); assert.equal(result.selected, first.selected);
    const css = renderer.nodes.get('gpt-niang-codex-wallpaper-style').textContent;
    assert.ok(css.includes(firstBytes.toString('base64')));
    assert.match(css, /rgba\(14, 15, 20, 0\.75\)/);
    assert.equal((await run('status', dir)).dimming, 75);
  } finally { fs.readFileSync = readFile; await closeCdp(server); }
});

test('invalid, missing, directory and tampered selections cannot change the saved wallpaper', async () => {
  const { dir, second } = await selectionFixture();
  const before = fs.readFileSync(path.join(dir, 'codex-wallpaper', 'state.json'), 'utf8');
  for (const name of ['../first.png', path.join(dir, 'first.png'), '', undefined]) await assert.rejects(run('select', dir, name), /没有可用/);
  await assert.rejects(run('select', dir, 'f'.repeat(64) + '.png'), /已不存在/);
  const directory = 'e'.repeat(64) + '.png';
  fs.mkdirSync(path.join(dir, 'codex-wallpaper', 'images', directory));
  await assert.rejects(run('select', dir, directory), /有效的已导入/);
  const tampered = 'd'.repeat(64) + '.png';
  fs.writeFileSync(path.join(dir, 'codex-wallpaper', 'images', tampered), png);
  await assert.rejects(run('select', dir, tampered), /校验失败/);
  assert.equal(fs.readFileSync(path.join(dir, 'codex-wallpaper', 'state.json'), 'utf8'), before);
  assert.equal((await run('status', dir)).selected, second.selected);
});

test('an unavailable Codex page keeps the choice and reports that application failed', async () => {
  const { dir, first } = await selectionFixture();
  const { server, port } = await mockCdp('app://other-app/home');
  try {
    await run('enable', dir);
    const result = await run('select', dir, first.selected, { port });
    assert.equal(result.applied, false); assert.equal(result.enabled, true);
    assert.match(result.warning, /没有找到 Codex 页面/);
    assert.equal((await run('status', dir)).selected, first.selected);
  } finally { await closeCdp(server); }
});

test('named imports save actual filenames and select them without name metadata', async () => {
  const { dir } = await selectionFixture();
  const firstFile = path.join(dir, 'first.png');
  const name = '海边 & 晴空 [1]';
  const imported = await run('import', dir, firstFile, { name });
  assert.equal(imported.selected, name + '.png');
  const saved = path.join(dir, 'codex-wallpaper', 'images', name + '.png');
  assert.deepEqual(fs.readFileSync(saved), fs.readFileSync(firstFile));
  const selected = await run('select', dir, imported.selected);
  assert.equal(selected.selected, name + '.png');
  const state = JSON.parse(fs.readFileSync(path.join(dir, 'codex-wallpaper', 'state.json')));
  assert.deepEqual(Object.keys(state).sort(), ['dimming', 'enabled', 'selected']);
  assert.equal(state.enabled, false);
});

test('same filenames preserve existing images and distinguish new content', async () => {
  const { dir } = await selectionFixture();
  const firstPath = path.join(dir, 'first.png'), secondPath = path.join(dir, 'second.png');
  fs.writeFileSync(secondPath, pngWithComment('other')); // Same byte length, different content.
  const first = await run('import', dir, firstPath, { name: '风景.PNG' });
  const duplicate = await run('import', dir, firstPath, { name: '风景.png' });
  const second = await run('import', dir, secondPath, { name: '风景' });
  assert.equal(first.selected, '风景.png');
  assert.equal(duplicate.selected, first.selected);
  assert.equal(second.selected, '风景 (2).png');
  assert.deepEqual(fs.readFileSync(path.join(dir, 'codex-wallpaper', 'images', first.selected)), fs.readFileSync(firstPath));
  assert.deepEqual(fs.readFileSync(path.join(dir, 'codex-wallpaper', 'images', second.selected)), fs.readFileSync(secondPath));
});

test('invalid import filenames do not create images or change selection', async () => {
  const { dir } = await selectionFixture();
  const stateFile = path.join(dir, 'codex-wallpaper', 'state.json');
  const before = fs.readFileSync(stateFile), images = path.join(dir, 'codex-wallpaper', 'images');
  const filesBefore = fs.readdirSync(images);
  for (const name of ['', ' ', '../outside', 'a\\b', 'C:outside', 'CON', 'nul.jpg', 'a*', 'a"b', 'line\nbreak', 'x'.repeat(81), 'a'.repeat(64)]) {
    await assert.rejects(run('import', dir, path.join(dir, 'first.png'), { name }), /文件名|壁纸/);
  }
  assert.deepEqual(fs.readFileSync(stateFile), before);
  assert.deepEqual(fs.readdirSync(images), filesBefore);
});

test('a manually renamed library file remains selectable and applies its bytes', async () => {
  const { dir, first, firstBytes } = await selectionFixture();
  const renamed = '自己重命名的图片.png';
  fs.renameSync(path.join(dir, 'codex-wallpaper', 'images', first.selected), path.join(dir, 'codex-wallpaper', 'images', renamed));
  await run('enable', dir);
  const { server, port, renderer } = await mockCdp();
  try {
    const result = await run('select', dir, renamed, { port });
    assert.equal(result.applied, true);
    assert.ok(renderer.nodes.get('gpt-niang-codex-wallpaper-style').textContent.includes(firstBytes.toString('base64')));
  } finally { await closeCdp(server); }
});
