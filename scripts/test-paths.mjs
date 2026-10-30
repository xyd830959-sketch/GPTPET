import path from 'node:path';

// Pure validation: reject unsafe roots before creating fixtures or spawning tests.
export function validateTestRoot(chosen, { source, userProfile, localAppData, platform = process.platform }) {
  const paths = platform === 'win32' ? path.win32 : path.posix;
  if (typeof chosen !== 'string' || !paths.isAbsolute(chosen)) throw new Error('A dedicated absolute test directory is required.');
  const resolved = paths.resolve(chosen);
  const key = value => {
    const normalized = paths.resolve(value);
    return platform === 'win32' ? normalized.toLowerCase() : normalized;
  };
  const base = key(resolved);
  const inside = value => base === key(value) || base.startsWith(key(value) + paths.sep);
  if (base === key(paths.parse(resolved).root) || inside(source) || userProfile && base === key(userProfile) || localAppData && (base === key(localAppData) || inside(paths.join(localAppData, 'GPTNiangUsage')) || inside(paths.join(localAppData, 'Programs', 'GPTNiangUsage')))) {
    throw new Error('Test root must not be the source, a drive root, the user profile or GPTNiangUsage personal data.');
  }
  return resolved;
}
