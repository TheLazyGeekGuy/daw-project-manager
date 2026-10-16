<#
.SYNOPSIS
  Runs the end-to-end tests (integration_test/) in the real app window, on the
  isolated test library — one file at a time.

.DESCRIPTION
  One `flutter test` per file, stopping any app a file leaves behind: the app
  runs as a single copy, and a single run over several files starts the next
  file's app before the last one has quit, so it is turned away.

.EXAMPLE
  scripts/run_integration_tests.ps1                 # all of them, full speed
  scripts/run_integration_tests.ps1 -Watch          # slowed down to follow
  scripts/run_integration_tests.ps1 -Filter project # files matching *project*
#>
param(
  [string] $Filter = '',
  [switch] $Watch
)
$repo = Split-Path -Parent $PSScriptRoot
$defines = @('--dart-define=DPM_DATA_DIR=daw_project_manager_uitest')
if ($Watch) { $defines += '--dart-define=UITEST_STEP_MS=800' }

$failed = @()
foreach ($f in Get-ChildItem (Join-Path $repo 'integration_test') -Filter "*$Filter*_test.dart") {
  Write-Host "`n=== $($f.Name)" -ForegroundColor Cyan
  flutter test $f.FullName -d windows @defines
  if ($LASTEXITCODE -ne 0) { $failed += $f.Name }
  Get-Process daw_project_manager -ErrorAction SilentlyContinue | Stop-Process -Force
}
if ($failed) { Write-Host "`nFailed: $($failed -join ', ')" -ForegroundColor Red; exit 1 }
Write-Host "`nAll end-to-end tests passed." -ForegroundColor Green
