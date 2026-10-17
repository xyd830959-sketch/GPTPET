import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import crypto from 'node:crypto';
import vm from 'node:vm';
import { run } from '../runtime/codex-wallpaper.mjs';

const outputRoot = path.resolve(import.meta.dirname, '..', '..', 'verification-data');
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

async function mockCdp(pageUrl = 'app://codex/home', dreamSkinActive = false) {
  const renderer = fakeRenderer(dreamSkinActive);
  const server = http.createServer((request, response) => {
    const port = server.address().port;
    response.setHeader('Content-Type', 'application/json');
    if (request.url === '/json/version') response.end(JSON.stringify({ webSocketDebuggerUrl: `ws://127.0.0.1:${port}/devtools/browser/test-browser` }));
    else if (request.url === '/json/list') response.end(JSON.stringify([{
      type: 'page', id: 'test-page', url: pageUrl,
      webSocketDebuggerUrl: `ws://127.0.0.1:${port}/devtools/page/test-page`,
    }]));
    else { response.statusCode = 404; response.end('{}'); }
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
      if ((pending[0] & 0x0f) !== 1) { pending = Buffer.alloc(0); return; }
      const mask = pending.subarray(offset, offset + 4);
      const payload = Buffer.from(pending.subarray(offset + 4, offset + 4 + length));
      for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i % 4];
      const message = JSON.parse(payload.toString('utf8'));
      let result;
      try { result = vm.runInNewContext(message.params.expression, renderer.context); }
      catch (error) { result = false; }
      const body = Buffer.from(JSON.stringify({ id: message.id, result: { result: { type: 'boolean', value: result } } }));
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
  } finally { await new Promise(resolve => server.close(resolve)); }
});

test('a different app on the same debug port is never modified', async () => {
  const { server, port, renderer } = await mockCdp('app://other-app/home');
  try {
    await run('enable', dataDir);
    await assert.rejects(run('apply', dataDir, undefined, { port }), /没有找到 Codex 页面/);
    assert.equal(renderer.nodes.size, 0);
  } finally {
    await new Promise(resolve => server.close(resolve));
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
    await new Promise(resolve => server.close(resolve));
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
    await new Promise(resolve => server.close(resolve));
    await run('disable', dataDir, undefined, { port });
  }
});
