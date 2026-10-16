<#
.SYNOPSIS
  Copies a DAW project into the test collection (test/fixtures/projects/<daw>/<name>/).

.DESCRIPTION
  Copies the project file and what sits around it in its folder — the samples
  and audio it may reference — leaving out other project files (a fixture is
  one project), backups and auto-saves, bounces/renders/freezes, and any file
  over -MaxFileMB. Stops if the copy would pass -MaxTotalMB: every byte here
  is in every clone of the repo, forever.

  With -Versions, the other project files in the folder come too: a folder
  of one song's versions (Song.flp, Song_2.flp…), which the app stacks.

  Then: UPDATE_FIXTURES=1 flutter test test/fixtures/project_corpus_test.dart
  writes its .expected.json — read it, then commit both.

.EXAMPLE
  scripts/add_test_fixture.ps1 -Daw ableton -Project "D:\MusicProduction\Projects\Ableton Live\Song Project\Song.als"
.EXAMPLE
  scripts/add_test_fixture.ps1 -Daw flstudio -Versions -MaxFileMB 1 -Project "D:\...\Song\Song.flp"
#>
param(
  [Parameter(Mandatory)] [ValidateSet('cubase', 'ableton', 'flstudio', 'reaper', 'studioone', 'bitwig', 'dawproject', 'protools')]
  [string] $Daw,
  [Parameter(Mandatory)] [string] $Project,
  [string] $Name,
  [int] $MaxFileMB = 8,
  [int] $MaxTotalMB = 40,
  [switch] $Versions
)
$ErrorActionPreference = 'Stop'

$projectFile = Get-Item -LiteralPath $Project
$source = $projectFile.Directory.FullName
if (-not $Name) {
  $Name = ($projectFile.BaseName -replace '[^A-Za-z0-9 _.-]', '' -replace '\s+', ' ').Trim()
}
$repo = Split-Path -Parent $PSScriptRoot
$dest = Join-Path $repo "test\fixtures\projects\$Daw\$Name"
if (Test-Path -LiteralPath $dest) { throw "Already in the collection: $dest" }

$projectExts = '.cpr', '.npr', '.als', '.flp', '.rpp', '.song', '.bwproject', '.dawproject', '.ptx', '.bak', '.rpp-bak'
$skipDirs = '(?i)\\(backups?|auto[- ]?saves?|autosave|bounces?|renders?|freeze|mixdown|exports?|history)(\\|$)'
$maxFile = $MaxFileMB * 1MB

# A folder holding other projects too (FL Studio keeps many songs in one) is
# not this project's: everything else in it belongs to the others, so only
# the project file comes in — unless they are its versions (-Versions).
$siblings = Get-ChildItem -LiteralPath $source -Recurse -File | Where-Object {
  $_.FullName -ne $projectFile.FullName -and ($projectExts -contains $_.Extension.ToLower()) -and
  $_.FullName.Substring($source.Length) -notmatch $skipDirs
}
if ($siblings -and -not $Versions) {
  "Shared folder ($($siblings.Count) other projects): copying the project file only."
  $files = @($projectFile)
} else {
if ($siblings) { "Versions: $($siblings.Count + 1) project files." }
$files = Get-ChildItem -LiteralPath $source -Recurse -File | Where-Object {
  $rel = $_.FullName.Substring($source.Length)
  if ($_.FullName -eq $projectFile.FullName) { return $true }
  if ($rel -match $skipDirs) { return $false }
  if ($projectExts -contains $_.Extension.ToLower()) {
    return $Versions -and $_.Extension.ToLower() -notin '.bak', '.rpp-bak'
  }
  if ($_.Name -match '(?i)autosave|\.peak$|\.reapeaks$|\.asd$|\.pk$|\.sfk$|\.csh$|\.lnk$|desktop\.ini|thumbs\.db') { return $false }
  return $_.Length -le $maxFile
}
}
$total = ($files | Measure-Object Length -Sum).Sum
if ($total -gt $MaxTotalMB * 1MB) {
  throw ("{0:N1} MB would go in, over -MaxTotalMB {1}. Pick a smaller project or raise the cap on purpose." -f ($total / 1MB), $MaxTotalMB)
}

foreach ($f in $files) {
  $target = Join-Path $dest $f.FullName.Substring($source.Length).TrimStart('\')
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
  Copy-Item -LiteralPath $f.FullName -Destination $target
}
"Copied {0} files ({1:N1} MB) to {2}" -f $files.Count, ($total / 1MB), $dest
"Next: `$env:UPDATE_FIXTURES='1'; flutter test test/fixtures/project_corpus_test.dart; Remove-Item Env:UPDATE_FIXTURES"
