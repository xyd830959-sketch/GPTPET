import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import {pluginVersion} from '../fox-spirit/runtime/metadata.mjs';

test('standalone fox runtime loads version metadata without a local plugin registration',()=>{
  const pkg=JSON.parse(fs.readFileSync(new URL('../fox-spirit/package.json',import.meta.url),'utf8'));
  assert.equal(pluginVersion,pkg.version);
  assert.equal(fs.existsSync(new URL('../fox-spirit/.codex-plugin/plugin.json',import.meta.url)),false);
});
