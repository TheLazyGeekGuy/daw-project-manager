# Website

dpm.bandpassrecords.com, built with [Astro](https://astro.build) and published to GitHub Pages by `.github/workflows/site.yml`.

```bash
cd website
npm install
npm run dev       # http://localhost:4321, reloads as you edit
npm run build     # dist/
npm run preview   # serves dist/
```

## Where things come from

| On the page | Source |
|---|---|
| Screenshots, DAW and OS logos | `../resources/` — copied into `public/resources/` by `scripts/sync-resources.mjs` before `dev` and `build`; never edit the copies |
| Supported DAWs, and what is read from each | `src/data/daws.ts` — the homepage grid and table and the guide's grid and matrix all draw from it |
| Download links | the newest GitHub release, read at build time (`src/lib/release.ts`); the release workflow rebuilds the site after publishing |
| What's new (`changelog.html`, the homepage's version badge) | `../assets/changelog/changelog.json`, the app's own changelog |
| `CNAME`, `.well-known/org.flatpak.VerifiedApps.txt` | `public/` — the domain, and Flathub's proof that the domain is ours |

Pages are built as `index.html`, `docs.html` and `changelog.html` (`build.format: 'file'`): installed apps link to `docs.html`.

## Moving off the gh-pages branch

1. Settings > Pages > Source: **GitHub Actions**.
2. Run the Website workflow (or push to `website/`).
3. Check `https://dpm.bandpassrecords.com/.well-known/org.flatpak.VerifiedApps.txt` still answers.
4. The `gh-pages` branch is no longer published; keep it for its history.
