# Website

dpm.bandpassrecords.com, built with [Astro](https://astro.build). `.github/workflows/site.yml` builds it and commits the result to the `gh-pages` branch, which GitHub Pages serves. Each published version is a commit there: to go back, revert it on `gh-pages`. Never edit `gh-pages` by hand — the next publish replaces it with what `website/` builds.

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
| What's new (`/changelog/`) | `../assets/changelog/changelog.json`, the app's own changelog |
| `CNAME`, `.well-known/org.flatpak.VerifiedApps.txt` | `public/` — the domain, and Flathub's proof that the domain is ours |
| `.nojekyll` | `public/` — without it Pages runs Jekyll, which drops Astro's `_astro/` folder (every script and stylesheet) |
| The user guide | `src/content/docs/guide/` — one page per section, served by [Starlight](https://starlight.astro.build) at `/guide/` with search; the sidebar is `src/data/guide-sidebar.json` |
| Palettes | `src/styles/theme.css` (homepage) and `src/styles/starlight.css` (guide): the app's Neon Dark and Classic Dark |

Installed apps open `docs.html`, often with an anchor (`docs.html#work-sessions`): `src/pages/docs.html.ts` sends each one to the guide page holding it (`src/data/guide-anchors.json`). A new guide page whose section had an anchor of its own needs it added there.
