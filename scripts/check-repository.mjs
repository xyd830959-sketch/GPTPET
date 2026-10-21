import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const failures = [], warnings = [];
function requireCondition(condition, label) { if (!condition) failures.push(label); }
function json(relative) { return JSON.parse(fs.readFileSync(path.join(root, relative), 'utf8').replace(/^\uFEFF/, '')); }
const manifest = json('.codex-plugin/plugin.json');
const pkg = json('package.json');
requireCondition(pkg.version === manifest.version, 'Package and plugin versions differ.');
requireCondition(/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(pkg.version), 'Invalid candidate version.');
requireCondition(pkg.private === true, 'Keep npm publication disabled unless separately authorized.');
requireCondition(pkg.engines.node === '>=22', 'Node engine must match built-in WebSocket requirement.');
requireCondition(manifest.interface.developerName.includes('xyd830959-sketch') && manifest.interface.developerName.includes('T7moris'), 'Maintainer and upstream attribution missing.');
const marketplace = json('.agents/plugins/marketplace.json');
requireCondition(marketplace.name === 'gpt-niang-local' && marketplace.plugins[0].name === manifest.name && marketplace.plugins[0].source.path === './', 'Local marketplace does not resolve this plugin.');
for (const icon of ['composerIcon', 'logo']) requireCondition(fs.existsSync(path.join(root, manifest.interface[icon])), `Missing ${icon}.`);
const originalCopyright = 'Copyright (c) 2026 Local GPT Niang Widget contributors';
requireCondition(fs.readFileSync(path.join(root, 'LICENSE'), 'utf8').includes(originalCopyright), 'Original v1.2.5 copyright missing.');
const required = ['README.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', 'CONTRIBUTING.md', 'SECURITY.md', 'CHANGELOG.md', 'assets/CHARACTER-NOTICE.txt', 'docs/PROVENANCE.md', 'docs/INSTALLATION.md', 'docs/COMPATIBILITY.md', 'docs/DEVELOPMENT.md', 'docs/RELEASE_CHECKLIST.md', '.github/workflows/ci.yml'];
for (const relative of required) requireCondition(fs.existsSync(path.join(root, relative)), `Missing ${relative}.`);
const skip = new Set(['.git', 'node_modules', 'work', 'dist', 'state', 'verification-data', 'experiment-data', 'test-results']);
const files = [];
function walk(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (skip.has(entry.name)) continue;
    const full = path.join(directory, entry.name);
    if (entry.isSymbolicLink()) { failures.push(`Symbolic link needs review: ${path.relative(root, full)}`); continue; }
    if (entry.isDirectory()) walk(full);
    else files.push(full);
  }
}
walk(root);
const secretPatterns = [
  ['GitHub credential', /\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{30,})\b/],
  ['API credential', /\bsk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{20,}\b/],
  ['private key', /^-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/m],
];
function scan(bytes, label, historical = false) {
  if (bytes.includes(0) || bytes.length > 2_000_000) return;
  const source = bytes.toString('utf8');
  for (const [kind, pattern] of secretPatterns) if (pattern.test(source)) failures.push(`${kind}: ${label} (value redacted)`);
  if (/[CD]:\\Users\\[^\\\r\n]+\\|D:\\codex工作区\\/.test(source)) {
    (historical ? warnings : failures).push(`Machine-specific path: ${label} (value redacted)`);
  }
}
for (const full of files) {
  const relative = path.relative(root, full).replaceAll('\\', '/');
  requireCondition(!/^(?:installation|auth|credentials)\.json$|^\.env(?:\.|$)|\.(?:pem|key)$/i.test(relative), `Personal configuration must not be distributed: ${relative}`);
  const bytes = fs.readFileSync(full);
  scan(bytes, relative);
  if (!relative.endsWith('.md')) continue;
  const source = bytes.toString('utf8');
  for (const match of source.matchAll(/\]\(([^)]+)\)/g)) {
    const target = match[1].split('#')[0];
    if (!target || /^[a-z][a-z0-9+.-]*:/i.test(target) || target.includes('<')) continue;
    let decoded;
    try { decoded = decodeURIComponent(target); } catch { failures.push(`Invalid link in ${relative}`); continue; }
    const destination = path.resolve(path.dirname(full), decoded);
    requireCondition(destination.startsWith(path.resolve(root) + path.sep) || destination === path.resolve(root), `Link escapes repository: ${relative}`);
    requireCondition(fs.existsSync(destination), `Broken local link: ${relative} -> ${target}`);
  }
}
let historyObjects = 0;
if (process.argv.includes('--history')) {
  const list = spawnSync('git', ['-c', 'core.quotePath=false', 'rev-list', '--objects', '--all'], { cwd: root, encoding: 'utf8', windowsHide: true });
  requireCondition(list.status === 0, 'History scan needs a readable Git repository.');
  if (list.status === 0) {
    for (const line of list.stdout.trim().split('\n')) {
      const space = line.indexOf(' ');
      if (space < 0) continue;
      const oid = line.slice(0, space), name = line.slice(space + 1).trim();
      const object = spawnSync('git', ['cat-file', '-p', oid], { cwd: root, windowsHide: true, maxBuffer: 8_000_000 });
      if (object.status !== 0) { failures.push(`Cannot inspect Git object ${oid}`); continue; }
      scan(object.stdout, `${name} @ ${oid.slice(0, 12)}`, true);
      historyObjects++;
    }
  }
}
const summary = { ok: failures.length === 0, checkedFiles: files.length, historyObjects, failures, warnings, limitations: ['Pattern-based scan only; binary assets and disclosure permissions need human review.', 'Historical machine paths require a disclosure decision before making existing history public.'] };
console.log(JSON.stringify(summary, null, 2));
process.exitCode = failures.length ? 1 : 0;
