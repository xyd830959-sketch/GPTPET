import test from 'node:test';
import assert from 'node:assert/strict';
import { validateTestRoot } from '../scripts/test-paths.mjs';

const context = { source: 'D:\\projects\\GPTPET', userProfile: 'C:\\Users\\fixture', localAppData: 'C:\\Users\\fixture\\AppData\\Local', platform: 'win32' };

test('test root cannot point at source using different Windows casing or normalized traversal', () => {
  for (const chosen of ['d:\\PROJECTS\\gptpet', 'D:\\projects\\GPTPET\\temporary', 'D:\\projects\\other\\..\\GPTPET']) {
    assert.throws(() => validateTestRoot(chosen, context), /must not/);
  }
});

test('test root refuses drive roots, user profile, personal data root and its descendants', () => {
  for (const chosen of ['D:\\', 'c:\\USERS\\fixture', context.localAppData, context.localAppData + '\\GPTNiangUsage', context.localAppData + '\\gptniangusage\\state', context.localAppData + '\\Programs\\GPTNiangUsage', context.localAppData + '\\Programs\\GPTNiangUsage\\gpt-niang-usage\\']) {
    assert.throws(() => validateTestRoot(chosen, context), /must not/);
  }
});

test('test root requires an absolute path and accepts a dedicated temporary directory', () => {
  for (const chosen of ['', 'work\\tests', 'D:tests']) assert.throws(() => validateTestRoot(chosen, context), /absolute/);
  const dedicated = context.localAppData + '\\Temp\\gptpet-tests';
  assert.equal(validateTestRoot(dedicated, context), dedicated);
  assert.equal(validateTestRoot('D:\\review-fixtures\\run', context), 'D:\\review-fixtures\\run');
});
