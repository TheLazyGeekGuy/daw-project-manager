<#
.SYNOPSIS
  Retakes the README's and the user guide's screenshots from the real app.

.DESCRIPTION
  Runs integration_test/screenshots/capture_test.dart in a desktop window
  on a library of demo data (never your own: it wipes and fills
  daw_project_manager_screenshots), with the version left out of the title,
  and writes resources/screenshots/<area>/<name>.png at 1920x1080.

  Copy what changed to the gh-pages branch's resources/screenshots/ for the
  website.

.EXAMPLE
  scripts/capture_screenshots.ps1
#>
$repo = Split-Path -Parent $PSScriptRoot
Push-Location $repo
try {
  flutter test integration_test/screenshots/capture_test.dart -d windows `
    --dart-define=DPM_DATA_DIR=daw_project_manager_screenshots `
    --dart-define=DPM_HIDE_VERSION=true `
    --dart-define=DPM_SCREENSHOTS=true
  $code = $LASTEXITCODE
} finally {
  Get-Process daw_project_manager -ErrorAction SilentlyContinue | Stop-Process -Force
  Pop-Location
}
exit $code
