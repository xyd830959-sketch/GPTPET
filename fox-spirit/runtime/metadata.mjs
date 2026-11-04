import fs from 'node:fs';

// The standalone preview must not require a registered Codex plugin manifest.
const manifest = JSON.parse(fs.readFileSync(new URL('../package.json', import.meta.url), 'utf8').replace(/^\uFEFF/, ''));
export const pluginVersion = manifest.version;
