import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {isLocalOnly,listDistributionFiles} from '../scripts/repository-files.mjs';
function fixture(){
  if(!process.env.GPTPET_TEST_ROOT)throw new Error('Use the isolated test runner.');
  return fs.mkdtempSync(path.join(os.tmpdir(),'distribution-'));
}
test('Git inventory excludes ignored local config but still exposes an accidentally tracked config',()=>{
  const root=fixture(),git=args=>execFileSync('git',args,{cwd:root,windowsHide:true,stdio:'pipe'});
  git(['init','--quiet']);fs.writeFileSync(path.join(root,'.gitignore'),'installation.json\nstate/\n');
  fs.writeFileSync(path.join(root,'installation.json'),'{}');fs.writeFileSync(path.join(root,'code.mjs'),'export const ready=true;');
  assert(!listDistributionFiles(root).some(p=>p.endsWith('installation.json')));
  assert(listDistributionFiles(root).some(p=>p.endsWith('code.mjs')));
  git(['add','-f','installation.json']);
  assert(listDistributionFiles(root).some(p=>p.endsWith('installation.json')),'Tracked private configuration must remain visible to the leak check.');
});
test('a source archive ignores local state without borrowing its parent repository',()=>{
  const root=fixture();fs.mkdirSync(path.join(root,'fox-spirit','state'),{recursive:true});
  fs.writeFileSync(path.join(root,'fox-spirit','installation.json'),'{}');
  fs.writeFileSync(path.join(root,'fox-spirit','installation.json.previous'),'{}');
  fs.writeFileSync(path.join(root,'fox-spirit','installation.json.new'),'{}');
  fs.writeFileSync(path.join(root,'fox-spirit','state','status.json'),'{}');
  fs.writeFileSync(path.join(root,'fox-spirit','code.mjs'),'export {};');
  assert.deepEqual(listDistributionFiles(root).map(p=>path.relative(root,p)),[path.join('fox-spirit','code.mjs')]);
  assert(isLocalOnly('fox-spirit/installation.json'));
  assert(!isLocalOnly('.env.example'));
});
