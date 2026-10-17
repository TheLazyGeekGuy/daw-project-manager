---
name: screenshots
description: Retake DAW Project Manager's screenshots from the real app on a demo library, review them, add screens that are missing, and publish them to the README and the website's user guide (gh-pages docs.html). Use when the user says "refresh the screenshots", "retake screenshots", "screenshots are outdated", "add a screenshot of …", or after a UI change the docs should show.
argument-hint: "[screen to add]"
---

# Screenshots

The pictures in `README.md` and on dpm.bandpassrecords.com come from code,
not from someone's desktop:

- `scripts/capture_screenshots.ps1` runs `integration_test/screenshots/capture_test.dart`
  in a real window, on a library of its own
  (`DPM_DATA_DIR=daw_project_manager_screenshots`; it refuses any other and
  wipes that one), with the version left out of the title
  (`DPM_HIDE_VERSION=true`).
- The seed is `DemoDataService` plus what a lived-in library has: MIDI read
  from the test collection, a collection with folders, a scan folder, a song
  in Recently deleted. Profiles are renamed Studio / Solo / Collab.
- Each screen is a `screen('name', () async { … })` block; one that can't be
  reached is reported in `SCREENSHOTS SKIPPED:` and the others still taken.
- Output: `resources/screenshots/<area>/<name>.png`, 1920×1080, Classic Dark.

Never point it at a real library. Windows only so far (it runs `-d windows`).

## 1. Retake

```powershell
scripts/capture_screenshots.ps1
```

About 2 minutes, after a ~40 s build. Close any running copy of the app
first — it runs as a single instance, and a debug build holding the exe
fails the build with LNK1168.

Read the last lines: `SCREENSHOTS SKIPPED: none` and `All tests passed!`.
A failed run with every screenshot taken still means something: the test
fails on any error the app logs — an overflow, a `dispose()` crash. **Treat
those as app bugs**, not tool noise: find the widget in the stack, fix it
with a regression test. (This tool's first runs found an overflowing queue
header and two `ref`-in-`dispose()` crashes.)

## 2. Review every picture

Open each changed PNG and look at it. What to catch:

- a screen that never got there (the dashboard again where a page should
  be — a tap that missed);
- empty states where content was meant to show (no clips, no folders) —
  seed more in `_seed()`;
- anything personal or odd: real paths, "Demo — …", a version number,
  "DEBUG" (the banner is off via `WidgetsApp.debugAllowBannerOverride`);
- yellow-black overflow stripes.

## 3. Adding a screen

Add a `screen(…)` block in `main()`. Helpers on the tester: `openTab(icon)`
(a rail tab), `tapOn(finder)`, `projectMenu(project, entry)` (right-click
menu), `back()`, `until(finder)`, `settle()`, `shot('area/name.png')`.

Lessons from writing these:

- Finders often match an offscreen copy (tabs keep their pages): use
  `.hitTestable()`, or pick by position (`localToGlobal`, as the release
  details button does — the pinned project in the top bar has the same icon).
- A `SegmentedButton` segment doesn't take a tap on its icon or tooltip; tap
  the button's rect at the segment's position.
- Material 3 `IconButton`s keep a 48 px target; after opening dialogs, give
  `settle(20)` for async loads.
- Seed data in `_seed()` before `app.main`: write through the repositories
  and stores (`ProjectRepository.init` first — it registers the adapters).

## 4. Publish

- **README** (`main`): references `resources/screenshots/…` directly; the
  feature tiles are a 2-column table.
- **Website** (`gh-pages` branch, `docs.html` / `index.html`): copy the
  changed files to the same paths under `gh-pages`'s `resources/screenshots/`.
  Work in a worktree of that branch; never push it without the user's go —
  it publishes the site.
- Commit the PNGs with the change that made them differ.
