import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://dpm.bandpassrecords.com',
  // docs.html, not docs/: the app links to https://dpm.bandpassrecords.com/docs.html
  // (dashboard, Settings > About, the macOS menu bar), and installed copies
  // keep those links for as long as they're in use.
  build: { format: 'file' },
});
