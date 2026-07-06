# Sheldon Loader installer — production channel.
# Usage: iex (irm https://raw.githubusercontent.com/projectsheldon/sheldon-binaries/main/install.ps1)
$ErrorActionPreference = 'Stop'
$manifestUrl = 'https://raw.githubusercontent.com/projectsheldon/sheldon-binaries/main/manifest.json'
$sevenZipUrl = 'https://github.com/projectsheldon/sheldon-binaries/raw/main/7zr.exe'
$installDir  = Join-Path $env:LOCALAPPDATA 'Sheldon'

Write-Host 'Fetching Sheldon manifest...' -ForegroundColor Cyan
$manifest = Invoke-RestMethod -Uri $manifestUrl
if (-not $manifest.loader_url) { Write-Host 'Manifest is missing loader_url.' -ForegroundColor Red; exit 1 }

Write-Host ("Loader v{0}" -f $manifest.loader_version) -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $installDir | Out-Null

# tar.exe on Windows only handles a subset of .7z codecs (no LZMA2), so we bootstrap
# the official 7zr.exe standalone extractor. Cache it in the install dir after first use.
$sevenZip = Join-Path $installDir '7zr.exe'
if (-not (Test-Path $sevenZip)) {
    Write-Host 'Fetching 7zr extractor...' -ForegroundColor Cyan
    Invoke-WebRequest -Uri $sevenZipUrl -OutFile $sevenZip -UseBasicParsing
}

$archive = Join-Path $installDir 'Loader.7z'
Write-Host 'Downloading Loader...' -ForegroundColor Cyan
Invoke-WebRequest -Uri $manifest.loader_url -OutFile $archive -UseBasicParsing

Write-Host 'Extracting...' -ForegroundColor Cyan
# -y = yes to all prompts, -o = output dir (no space, must be joined to path)
& $sevenZip x $archive "-o$installDir" -y | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host ("7zr exit code $LASTEXITCODE — extraction failed") -ForegroundColor Red
    exit 1
}
Remove-Item $archive -Force

$loader = Get-ChildItem -Path $installDir -Filter 'Loader.exe' -Recurse -File | Select-Object -First 1
if (-not $loader) { Write-Host 'Loader.exe not found after extraction.' -ForegroundColor Red; exit 1 }

Write-Host ("Launching {0}" -f $loader.FullName) -ForegroundColor Green
Start-Process -FilePath $loader.FullName
