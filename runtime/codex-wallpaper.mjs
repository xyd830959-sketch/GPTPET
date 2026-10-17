import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const MAX_BYTES = 10 * 1024 * 1024;
const STYLE_ID = 'gpt-niang-codex-wallpaper-style';
const ROOT_ATTRIBUTE = 'data-gpt-niang-codex-wallpaper';
const DEFAULT_DIMMING = 60;

function dimmingValue(value) {
  return Number.isInteger(value) && value >= 20 && value <= 85 ? value : DEFAULT_DIMMING;
}

function imageInfo(bytes) {
  let mime, extension, width, height;
  if (bytes.length >= 24 && bytes.subarray(0, 8).equals(Buffer.from('89504e470d0a1a0a', 'hex')) && bytes.toString('ascii', 12, 16) === 'IHDR') {
    if (bytes.length < 45 || !bytes.subarray(-12).equals(Buffer.from('0000000049454e44ae426082', 'hex'))) throw new Error('PNG 图片不完整。');
    mime = 'image/png'; extension = '.png';
    width = bytes.readUInt32BE(16); height = bytes.readUInt32BE(20);
  } else if (bytes.length >= 4 && bytes[0] === 0xff && bytes[1] === 0xd8) {
    if (bytes[bytes.length - 2] !== 0xff || bytes[bytes.length - 1] !== 0xd9) throw new Error('JPG 图片不完整。');
    mime = 'image/jpeg'; extension = '.jpg';
    let offset = 2;
    while (offset + 4 < bytes.length) {
      if (bytes[offset] !== 0xff) break;
      const marker = bytes[offset + 1];
      if (marker === 0xd9 || marker === 0xda) break;
      if (marker === 0xff || marker === 0x00 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) { offset += 2; continue; }
      const length = bytes.readUInt16BE(offset + 2);
      if (length < 2 || offset + 2 + length > bytes.length) break;
      if ([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf].includes(marker)) {
        if (length < 7) break;
        height = bytes.readUInt16BE(offset + 5); width = bytes.readUInt16BE(offset + 7); break;
      }
      offset += 2 + length;
    }
  } else if (bytes.length >= 30 && bytes.toString('ascii', 0, 4) === 'RIFF' && bytes.toString('ascii', 8, 12) === 'WEBP') {
    if (bytes.readUInt32LE(4) + 8 !== bytes.length) throw new Error('WebP 图片不完整。');
    mime = 'image/webp'; extension = '.webp';
    const kind = bytes.toString('ascii', 12, 16);
    if (kind === 'VP8X' && bytes.length >= 30) {
      width = bytes.readUIntLE(24, 3) + 1; height = bytes.readUIntLE(27, 3) + 1;
    } else if (kind === 'VP8 ' && bytes.length >= 30 && bytes[23] === 0x9d && bytes[24] === 0x01 && bytes[25] === 0x2a) {
      width = bytes.readUInt16LE(26) & 0x3fff; height = bytes.readUInt16LE(28) & 0x3fff;
    } else if (kind === 'VP8L' && bytes.length >= 25 && bytes[20] === 0x2f) {
      const bits = bytes.readUInt32LE(21);
      width = (bits & 0x3fff) + 1; height = ((bits >>> 14) & 0x3fff) + 1;
    }
  }
  if (!mime || !width || !height || width > 16384 || height > 16384 || width * height > 50_000_000) {
    throw new Error('图片无效、格式不支持，或尺寸超过限制。');
  }
  return { mime, extension, width, height };
}

function statePaths(dataDir) {
  const root = path.join(dataDir, 'codex-wallpaper');
  return { root, images: path.join(root, 'images'), state: path.join(root, 'state.json') };
}

function loadState(paths) {
  try {
    const value = JSON.parse(fs.readFileSync(paths.state, 'utf8'));
    return { enabled: value.enabled === true, selected: typeof value.selected === 'string' ? value.selected : null, dimming: dimmingValue(value.dimming), port: 9335 };
  } catch (error) {
    if (error.code === 'ENOENT') return { enabled: false, selected: null, dimming: DEFAULT_DIMMING, port: 9335 };
    throw new Error('壁纸设置无法读取，操作已停止。');
  }
}

function saveState(paths, state) {
  fs.mkdirSync(paths.root, { recursive: true });
  const temp = `${paths.state}.${process.pid}.${crypto.randomUUID()}.tmp`;
  fs.writeFileSync(temp, JSON.stringify({ enabled: state.enabled, selected: state.selected, dimming: state.dimming }, null, 2), { flag: 'wx' });
  fs.renameSync(temp, paths.state);
}

function imagePath(paths, selected) {
  if (!/^[a-f0-9]{64}\.(png|jpg|webp)$/.test(selected || '')) throw new Error('没有可用的已导入壁纸。');
  return path.join(paths.images, selected);
}

function validateEndpoint(value, port, targetId, kind) {
  const url = new URL(value);
  const validPath = new RegExp(`^/devtools/${kind}/[A-Za-z0-9._-]{1,200}$`);
  if (url.protocol !== 'ws:' || !['127.0.0.1', 'localhost', '[::1]', '::1'].includes(url.hostname) ||
      Number(url.port) !== port || url.username || url.password || url.search || url.hash || !validPath.test(url.pathname) ||
      (targetId && url.pathname !== `/devtools/${kind}/${targetId}`)) {
    throw new Error('调试连接地址未通过本机安全校验。');
  }
  return url.href;
}

async function cdpTargets(port) {
  const base = `http://127.0.0.1:${port}`;
  let version, targets;
  try {
    [version, targets] = await Promise.all(['/json/version', '/json/list'].map(async resource => {
      const response = await fetch(base + resource, { signal: AbortSignal.timeout(1500), redirect: 'error' });
      if (!response.ok) throw new Error('CDP HTTP error');
      return response.json();
    }));
  } catch {
    throw new Error(`未找到 Codex 调试连接（127.0.0.1:${port}）。请通过支持 CDP 的方式启动 Codex 后重试。`);
  }
  validateEndpoint(version.webSocketDebuggerUrl, port, null, 'browser');
  const pages = Array.isArray(targets) ? targets.filter(target =>
    target?.type === 'page' && typeof target.id === 'string' && /^[A-Za-z0-9._-]{1,200}$/.test(target.id) &&
    typeof target.url === 'string' &&
    (target.url === 'app://-/index.html' || /^app:\/\/codex(?:\/|$)/.test(target.url)) &&
    !target.url.includes('avatar-overlay') && typeof target.webSocketDebuggerUrl === 'string') : [];
  if (!pages.length) throw new Error('调试连接中没有找到 Codex 页面。');
  return pages.map(page => ({ ...page, socket: validateEndpoint(page.webSocketDebuggerUrl, port, page.id, 'page') }));
}

async function evaluate(socketUrl, expression) {
  const socket = new WebSocket(socketUrl);
  try {
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Codex 连接超时。')), 2500);
      socket.addEventListener('open', () => { clearTimeout(timeout); resolve(); }, { once: true });
      socket.addEventListener('error', () => { clearTimeout(timeout); reject(new Error('无法连接 Codex 页面。')); }, { once: true });
    });
    const result = await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error('Codex 页面未响应。')), 3000);
      socket.addEventListener('message', event => {
        let message;
        try { message = JSON.parse(String(event.data)); } catch { return; }
        if (message.id !== 1) return;
        clearTimeout(timeout);
        if (message.error || message.result?.exceptionDetails) reject(new Error('Codex 页面拒绝了壁纸操作。'));
        else resolve(message.result?.result?.value);
      });
      socket.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { expression, returnByValue: true, awaitPromise: false } }));
    });
    return result;
  } finally { socket.close(); }
}

function rendererExpression(action, dataUrl, dimming) {
  const alpha = (dimming / 100).toFixed(2);
  const css = action === 'apply' ? `
html[${ROOT_ATTRIBUTE}="on"] body { background: #17191e url(${JSON.stringify(dataUrl)}) center center / cover fixed no-repeat !important; }
html[${ROOT_ATTRIBUTE}="on"] #root, html[${ROOT_ATTRIBUTE}="on"] [data-app-shell-page-surface="true"] { background: transparent !important; }
html[${ROOT_ATTRIBUTE}="on"] [data-app-shell-main-surface] { background: rgba(14, 15, 20, ${alpha}) !important; }
html[${ROOT_ATTRIBUTE}="on"] [data-app-shell-main-surface] [data-app-action-timeline-scroll] [aria-hidden="true"][class~="pointer-events-none"][class~="bottom-0"][class~="bg-surface"],
html[${ROOT_ATTRIBUTE}="on"] [data-app-shell-main-surface] [data-app-action-timeline-scroll] [aria-hidden="true"][class~="pointer-events-none"][class~="from-surface"] { background: transparent !important; }
` : '';
  return `(() => {
    const id = ${JSON.stringify(STYLE_ID)};
    const attr = ${JSON.stringify(ROOT_ATTRIBUTE)};
    if (${JSON.stringify(action)} === 'restore') {
      document.getElementById(id)?.remove();
      document.documentElement.removeAttribute(attr);
      return !document.getElementById(id) && !document.documentElement.hasAttribute(attr);
    }
    if (window.__CODEX_DREAM_SKIN_STATE__) return 'dream-skin-active';
    if (!document.body || !(document.getElementById('root') || document.querySelector('[data-app-shell-page-surface="true"]'))) return 'unsupported-layout';
    let style = document.getElementById(id);
    if (!style) { style = document.createElement('style'); style.id = id; document.head.appendChild(style); }
    style.textContent = ${JSON.stringify(css)};
    document.documentElement.setAttribute(attr, 'on');
    return !!document.getElementById(id) && document.documentElement.getAttribute(attr) === 'on';
  })()`;
}

async function perform(action, paths, state) {
  const pages = await cdpTargets(state.port);
  let success = 0;
  let lastError;
  let dataUrl = '';
  if (action === 'apply') {
    const selectedPath = imagePath(paths, state.selected);
    if (fs.statSync(selectedPath).size > MAX_BYTES) throw new Error('壁纸超过 10 MB。');
    const bytes = fs.readFileSync(selectedPath);
    const { mime } = imageInfo(bytes);
    if (bytes.length > MAX_BYTES) throw new Error('壁纸超过 10 MB。');
    if (crypto.createHash('sha256').update(bytes).digest('hex') !== state.selected.slice(0, 64)) throw new Error('壁纸文件校验失败。');
    dataUrl = `data:${mime};base64,${bytes.toString('base64')}`;
  }
  for (const page of pages) {
    try {
      const result = await evaluate(page.socket, rendererExpression(action, dataUrl, state.dimming));
      if (result === true) success++;
      else if (result === 'dream-skin-active') lastError = new Error('Codex Dream Skin 正在使用中，请先暂停它再应用 GPT 娘壁纸。');
      else if (result === 'unsupported-layout') lastError = new Error('当前 Codex 页面结构暂不支持壁纸。');
    } catch (error) { lastError = error; }
  }
  if (!success) throw new Error(lastError?.message || '壁纸操作未能在 Codex 页面生效。');
  return { pages: success };
}

export async function run(command, dataDir, sourcePath, options = {}) {
  if (!path.isAbsolute(dataDir)) throw new Error('实验数据目录无效。');
  const paths = statePaths(dataDir);
  const state = loadState(paths);
  if (options.port !== undefined) {
    if (!Number.isInteger(options.port) || options.port < 1024 || options.port > 65535) throw new Error('调试端口无效。');
    state.port = options.port;
  }
  if (command === 'status') return { ...state, selectedName: state.selected ? state.selected : null };
  if (command === 'enable') { state.enabled = true; saveState(paths, state); return { enabled: true }; }
  if (command === 'set-dimming') {
    const dimming = Number(sourcePath);
    if (!Number.isInteger(dimming) || dimming < 20 || dimming > 85) throw new Error('壁纸明暗值无效。');
    state.dimming = dimming; saveState(paths, state);
    if (state.enabled && state.selected) {
      try { return { dimming, ...(await perform('apply', paths, state)) }; }
      catch (error) { return { dimming, warning: error.message }; }
    }
    return { dimming };
  }
  if (command === 'disable') {
    state.enabled = false; saveState(paths, state);
    try { await perform('restore', paths, state); return { enabled: false, restored: true }; }
    catch (error) { return { enabled: false, restored: false, warning: error.message }; }
  }
  if (command === 'import') {
    if (!sourcePath || !path.isAbsolute(sourcePath)) throw new Error('请选择本地图片。');
    if (fs.statSync(sourcePath).size > MAX_BYTES) throw new Error('壁纸必须是 10 MB 以内的 PNG、JPG 或 WebP 图片。');
    const bytes = fs.readFileSync(sourcePath);
    if (!bytes.length || bytes.length > MAX_BYTES) throw new Error('壁纸必须是 10 MB 以内的 PNG、JPG 或 WebP 图片。');
    const info = imageInfo(bytes);
    const hash = crypto.createHash('sha256').update(bytes).digest('hex');
    const name = hash + info.extension;
    fs.mkdirSync(paths.images, { recursive: true });
    try { fs.writeFileSync(imagePath(paths, name), bytes, { flag: 'wx' }); }
    catch (error) {
      if (error.code !== 'EEXIST') throw error;
      const existing=fs.readFileSync(imagePath(paths, name));
      if (crypto.createHash('sha256').update(existing).digest('hex') !== hash) throw new Error('同名壁纸文件内容不一致，已停止导入。');
    }
    state.selected = name; saveState(paths, state);
    return { selected: name, width: info.width, height: info.height };
  }
  if (command === 'apply') {
    if (!state.enabled) throw new Error('请先启用壁纸功能。');
    const result = await perform('apply', paths, state);
    return { applied: true, ...result };
  }
  if (command === 'restore') return { restored: true, ...(await perform('restore', paths, state)) };
  throw new Error('未知的壁纸操作。');
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [command, dataDir, sourcePath, resultFile] = process.argv.slice(2);
  try {
    const result = await run(command, dataDir, sourcePath);
    if (resultFile) fs.writeFileSync(resultFile, JSON.stringify({ ok: true, ...result }), { flag: 'w' });
    else console.log(JSON.stringify({ ok: true, ...result }));
  } catch (error) {
    const value = { ok: false, error: error.message };
    if (resultFile) fs.writeFileSync(resultFile, JSON.stringify(value), { flag: 'w' });
    else console.error(JSON.stringify(value));
    process.exitCode = 1;
  }
}
