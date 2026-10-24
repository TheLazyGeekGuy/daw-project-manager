---
name: screenshots
description: Retake DAW Project Manager's screenshots from the real app on a demo library, review them, add screens that are missing, and publish them to the README and the website's user guide (website/, docs.html). Use when the user says "refresh the screenshots", "retake screenshots", "screenshots are outdated", "add a screenshot of …", or after a UI change the docs should show.
argument-hint: "[screen to add]"
---

# Screenshots

The pictures in `README.md` and on dpm.bandpassrecords.com come from code,
not from someone's desktop:

- `scripts/capture_screenshots.ps1` runs `integration_test/screenshots/capture_test.dart`
  in a real window, on a library of its own
  (`DPM_DATA_DIR=daw_project_manager_screenshots`; it refuses any other and
  wipes that one), with the version left out of the title
  (`DPM_HIDE_VERSION=true`) and the debug-only developer tools hidden
  (`DPM_SCREENSHOTS=true`, read as `showDeveloperTools` in
  `lib/utils/screenshot_mode.dart`).
- Project pages are shot in the **Sections** layout (`projectDetailLayout`
  is seeded `sectioned`): a section at a time, picked from the rail.
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
- **developer tools** — anything a user's build doesn't have. The tool runs a
  debug build, so a debug-only control is on screen unless it is gated on
  `showDeveloperTools` (not `kDebugMode`). The Profile Manager's
  *Generate / Remove Testing Database* buttons were in its picture until they
  were. `shot()` refuses a picture showing any text in `_neverInAPicture`:
  gate a new developer tool on `showDeveloperTools` and add its label there;
- a song that shows nothing for the screen's subject (a to-do list with every
  item done, a session history with no sessions): pick another demo song, or
  seed what it lacks;
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

## 4. What the user guide says — and leaves out

The guide is for people making music, not for people working on the app.
Say what they can do and where; leave out how the app does it inside, and
anything they never need to think about. Removed for that reason:

- "Cubase reads back to SX 3; FL Studio back to FL 7; Ableton Live back to
  Live 8." — which versions the readers were tested against. That belongs in
  `docs/testing.md`, for developers.
- "A value read wrong? Type over it on the project's page: what you type wins
  over later scans." — how typed values and scanned ones are merged.

The same goes for pictures: no developer tools (above), no debug output.

## 5. Publish

- **README** (`main`): references `resources/screenshots/…` directly; the
  feature tiles are a 2-column table.
- **Website** (`website/`, `src/pages/docs.astro` / `index.astro`): it serves
  `resources/screenshots/` itself, so a retaken picture needs nothing more. A
  new one is referenced as `resources/screenshots/<area>/<name>.png`; check it
  with `npm run dev` in `website/`. Merging to `main` publishes the site.
- Commit the PNGs with the change that made them differ.
