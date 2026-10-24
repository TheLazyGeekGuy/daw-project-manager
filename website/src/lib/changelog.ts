// The app's own changelog (assets/changelog/changelog.json), the one the
// "What's New" dialog and Settings > Changelog show. The site reads it at build
// time rather than keeping release notes of its own.
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

export interface ChangelogRelease {
  version: string;
  date: string;
  highlights: Record<string, string[]>;
}

// npm scripts run from website/, so the repository is one level up.
const file = resolve(process.cwd(), '..', 'assets', 'changelog', 'changelog.json');

export function changelog(): ChangelogRelease[] {
  const json = JSON.parse(readFileSync(file, 'utf-8')) as { releases: ChangelogRelease[] };
  return json.releases;
}

/** A release's highlights in [locale], falling back to English as the app does. */
export function highlightsOf(release: ChangelogRelease, locale = 'en'): string[] {
  return release.highlights[locale] ?? release.highlights.en ?? [];
}
