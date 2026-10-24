// The download links, read from the newest GitHub release when the site is
// built. The release workflow rebuilds the site after publishing, which is what
// used to be a `sed` over index.html on the gh-pages branch.

const repo = 'bandpassrecords/daw-project-manager';
export const repoUrl = `https://github.com/${repo}`;
export const releasesUrl = `${repoUrl}/releases`;
export const storeUrl = 'https://apps.microsoft.com/detail/9n8hxzd3hwx7';

export interface Downloads {
  /** e.g. "v2.9.3"; null when GitHub couldn't be reached. */
  tag: string | null;
  /** The self-updating Setup when the release has one, else the Inno installer. */
  windowsInstaller: string;
  macos: string;
  linuxAppImage: string;
}

interface Asset {
  name: string;
  browser_download_url: string;
}

const patterns = {
  windowsSetup: /^DAW_Project_Manager_Setup_.*\.exe$/,
  windowsInstaller: /^DAW_Project_Manager_Installer_.*\.exe$/,
  macos: /^DAW_Project_Manager_macOS_.*\.dmg$/,
  linuxAppImage: /^DAW_Project_Manager_Linux_.*\.AppImage$/,
};

let cached: Promise<Downloads> | undefined;

/** Read once per build: both pages ask. */
export function latestDownloads(): Promise<Downloads> {
  return (cached ??= fetchLatest());
}

async function fetchLatest(): Promise<Downloads> {
  // Nothing found still builds a working page: every button opens the
  // latest release, where the files are.
  const fallback = `${releasesUrl}/latest`;
  try {
    const headers: Record<string, string> = { Accept: 'application/vnd.github+json' };
    if (process.env.GITHUB_TOKEN) headers.Authorization = `Bearer ${process.env.GITHUB_TOKEN}`;
    const response = await fetch(`https://api.github.com/repos/${repo}/releases/latest`, { headers });
    if (!response.ok) throw new Error(`GitHub answered ${response.status}`);
    const release = (await response.json()) as { tag_name: string; assets: Asset[] };
    const asset = (pattern: RegExp) =>
      release.assets.find((a) => pattern.test(a.name))?.browser_download_url;
    const find = (pattern: RegExp) => asset(pattern) ?? fallback;
    return {
      tag: release.tag_name,
      // Newcomers get the Setup that updates itself; the Inno installer stays
      // on the release for the copies it installed.
      windowsInstaller: asset(patterns.windowsSetup) ?? find(patterns.windowsInstaller),
      macos: find(patterns.macos),
      linuxAppImage: find(patterns.linuxAppImage),
    };
  } catch (error) {
    console.warn(`[release] latest release not read, linking to ${fallback}: ${error}`);
    return { tag: null, windowsInstaller: fallback, macos: fallback, linuxAppImage: fallback };
  }
}
