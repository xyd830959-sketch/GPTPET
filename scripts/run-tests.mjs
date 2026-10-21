import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { validateTestRoot } from './test-paths.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const chosen = process.env.GPTPET_TEST_ROOT;
if (!chosen || !path.isAbsolute(chosen) || process.env.GPTPET_ALLOW_TEST_CLEANUP !== '1') {
  console.error('Choose an absolute GPTPET_TEST_ROOT and explicitly set GPTPET_ALLOW_TEST_CLEANUP=1 for synthetic fixture cleanup. See docs/DEVELOPMENT.md.');
  process.exit(2);
}
const base = validateTestRoot(chosen, { source: root, userProfile: os.homedir(), localAppData: process.env.LOCALAPPDATA });
fs.mkdirSync(base, { recursive: true });
if (fs.realpathSync(base).toLowerCase() !== base.toLowerCase()) throw new Error('Test root must not redirect through a link.');
const runRoot = fs.mkdtempSync(path.join(base, 'run-'));
const env = { ...process.env, GPTPET_TEST_ROOT: runRoot, TEMP: runRoot, TMP: runRoot, TMPDIR: runRoot };
const reports = [];
let failure = false;
function run(label, command, args) {
  const result = spawnSync(command, args, { cwd: root, env, encoding: 'utf8', windowsHide: true, timeout: 180_000, maxBuffer: 8_000_000 });
  const output = (result.stdout || '') + (result.stderr || '') + (result.error ? '\n' + result.error.message : '');
  fs.writeFileSync(path.join(runRoot, label + '.log'), output);
  process.stdout.write(output);
  reports.push({ label, status: result.status, signal: result.signal, error: result.error?.message ?? null });
  if (result.status !== 0) failure = true;
}
if (!process.argv.includes('--windows-only')) {
  const tests = fs.readdirSync(path.join(root, 'tests')).filter(name => name.endsWith('.test.mjs')).sort().map(name => path.join('tests', name));
  run('node-tests', process.execPath, ['--test', ...tests]);
}
if (!process.argv.includes('--node-only')) {
  if (process.platform !== 'win32') { console.error('Full suite requires Windows; use --node-only elsewhere.'); failure = true; }
  else run('windows-tests', path.join(process.env.WINDIR, 'System32', 'WindowsPowerShell', 'v1.0', 'powershell.exe'), ['-NoProfile', '-STA', '-ExecutionPolicy', 'Bypass', '-File', 'tests/run-windows-tests.ps1', '-PreviewDirectory', path.join(runRoot, 'previews')]);
}
fs.writeFileSync(path.join(runRoot, 'summary.json'), JSON.stringify({ ok: !failure, node: process.version, platform: process.platform, reports }, null, 2));
console.log(`Test evidence retained: ${runRoot}`);
process.exitCode = failure ? 1 : 0;
