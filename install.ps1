# Sheldon Loader installer — production channel.
# Usage: iex (irm https://raw.githubusercontent.com/projectsheldon/sheldon-binaries/main/install.ps1)
$ErrorActionPreference = 'Stop'
$manifestUrl = 'https://raw.githubusercontent.com/projectsheldon/sheldon-binaries/main/manifest.json'
$installDir  = Join-Path $env:LOCALAPPDATA 'Sheldon'

Write-Host 'Fetching Sheldon manifest...' -ForegroundColor Cyan
$manifest = Invoke-RestMethod -Uri $manifestUrl
if (-not $manifest.loader_url) { Write-Host 'Manifest is missing loader_url.' -ForegroundColor Red; exit 1 }

Write-Host ("Loader v{0}" -f $manifest.loader_version) -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
$archive = Join-Path $installDir 'Loader.7z'

Write-Host 'Downloading...' -ForegroundColor Cyan
Invoke-WebRequest -Uri $manifest.loader_url -OutFile $archive -UseBasicParsing

Write-Host 'Extracting...' -ForegroundColor Cyan
& tar.exe -xf $archive -C $installDir
Remove-Item $archive -Force

$loader = Get-ChildItem -Path $installDir -Filter 'Loader.exe' -Recurse -File | Select-Object -First 1
if (-not $loader) { Write-Host 'Loader.exe not found after extraction.' -ForegroundColor Red; exit 1 }

Write-Host ("Launching {0}" -f $loader.FullName) -ForegroundColor Green
Start-Process -FilePath $loader.FullName
