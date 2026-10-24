// Copies the pictures the site shows from the app's own resources/ into
// public/resources/, so the screenshots the screenshot tool writes and the
// DAW logos the app ships are the ones the site serves — never a second copy
// kept by hand. Runs before `dev` and `build`; public/resources is ignored.
import { cpSync, rmSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const site = join(dirname(fileURLToPath(import.meta.url)), '..');
const repo = join(site, '..');
const out = join(site, 'public', 'resources');

// Only what the pages use: resources/ also holds tools (ffmpeg.exe) and
// build inputs that have no business on a website.
const folders = ['screenshots', join('daw', 'logos'), 'os'];
const pictures = /\.(png|jpe?g|gif|webp|svg)$/i;

rmSync(out, { recursive: true, force: true });
for (const folder of folders) {
  const from = join(repo, 'resources', folder);
  if (!existsSync(from)) throw new Error(`Missing ${from}`);
  cpSync(from, join(out, folder), {
    recursive: true,
    filter: (path) => !/\.[^\\/]+$/.test(path) || pictures.test(path),
  });
}
console.log(`resources → ${out}`);
