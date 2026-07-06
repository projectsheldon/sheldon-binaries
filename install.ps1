# Sheldon Loader installer — production channel.
# Usage: iex (irm https://raw.githubusercontent.com/projectsheldon/sheldon-binaries/main/install.ps1)
$ErrorActionPreference = 'Stop'
$manifestUrl = 'https://raw.githubusercontent.com/projectsheldon/sheldon-binaries/main/manifest.json'
$sevenZipUrl = 'https://github.com/projectsheldon/sheldon-binaries/raw/main/7zr.exe'

# Pick install location. Desktop is the default because it's visible/easy to find; users
# can type N to install into the current working directory instead. GetFolderPath('Desktop')
# respects OneDrive redirection when it's active.
$desktopDir = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Sheldon'
$cwdDir     = Join-Path (Get-Location).Path 'Sheldon'
$loc = Read-Host 'Install to Desktop? Press Enter for Desktop, or type N to install here (current folder) [Y/n]'
if ($loc -match '^[Nn]') {
    $installDir = $cwdDir
} else {
    $installDir = $desktopDir
}
Write-Host ("Installing to {0}" -f $installDir) -ForegroundColor DarkGray

function Invoke-Extract($archivePath, $destDir, $sevenZipPath) {
    & $sevenZipPath x $archivePath "-o$destDir" -y | Out-Null
    return $LASTEXITCODE
}

function Get-LoaderArchive($url, $dest) {
    Remove-Item $dest -Force -ErrorAction SilentlyContinue
    Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
}

Write-Host 'Fetching Sheldon manifest...' -ForegroundColor Cyan
$manifest = Invoke-RestMethod -Uri $manifestUrl
if (-not $manifest.loader_url) { Write-Host 'Manifest is missing loader_url.' -ForegroundColor Red; exit 1 }

Write-Host ("Loader v{0}" -f $manifest.loader_version) -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $installDir | Out-Null

# tar.exe on Windows can't handle LZMA2 (default 7z codec), so we bootstrap the
# official 7zr.exe standalone extractor. Cached after first use.
$sevenZip = Join-Path $installDir '7zr.exe'
if (-not (Test-Path $sevenZip)) {
    Write-Host 'Fetching 7zr extractor...' -ForegroundColor Cyan
    Invoke-WebRequest -Uri $sevenZipUrl -OutFile $sevenZip -UseBasicParsing
}

$archive = Join-Path $installDir 'Loader.7z'
Write-Host 'Downloading Loader...' -ForegroundColor Cyan
Get-LoaderArchive $manifest.loader_url $archive

Write-Host 'Extracting...' -ForegroundColor Cyan
$code = Invoke-Extract $archive $installDir $sevenZip

if ($code -ne 0) {
    Write-Host ''
    Write-Host 'Extraction failed. This is almost always Windows Defender flagging the binary.' -ForegroundColor Yellow
    Write-Host ("Add '{0}' to Defender's exclusion list, then retry the install?" -f $installDir) -ForegroundColor Yellow
    Write-Host '(requires a one-time UAC prompt for admin rights)' -ForegroundColor DarkGray
    $ans = Read-Host 'Add exclusion and retry? [Y/n]'
    if ($ans -eq '' -or $ans -match '^[Yy]') {
        Write-Host 'Requesting admin rights to add the exclusion...' -ForegroundColor Cyan
        # Elevate briefly to add both a path exclusion (covers Loader.7z, extracted files)
        # and process exclusions for the two binaries so they can run without runtime scans.
        $exclusionScript = @"
Add-MpPreference -ExclusionPath '$installDir' -ErrorAction SilentlyContinue
Add-MpPreference -ExclusionProcess 'Loader.exe' -ErrorAction SilentlyContinue
Add-MpPreference -ExclusionProcess 'Sheldon.exe' -ErrorAction SilentlyContinue
"@
        try {
            $proc = Start-Process -FilePath powershell.exe `
                -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-Command', $exclusionScript `
                -Verb RunAs -Wait -PassThru -WindowStyle Hidden
        } catch {
            Write-Host 'You declined admin rights or the elevation was blocked. Aborting.' -ForegroundColor Red
            Write-Host ("You can add the exclusion manually in Windows Security > Virus & threat protection > Exclusions, then point it at: {0}" -f $installDir) -ForegroundColor DarkGray
            exit 1
        }
        if ($proc.ExitCode -ne 0) {
            Write-Host ("Elevated shell exited with code {0}. Aborting." -f $proc.ExitCode) -ForegroundColor Red
            exit 1
        }

        Write-Host 'Exclusion added. Redownloading and re-extracting...' -ForegroundColor Cyan
        Get-LoaderArchive $manifest.loader_url $archive
        $code = Invoke-Extract $archive $installDir $sevenZip
        if ($code -ne 0) {
            Write-Host ("7zr exit code {0} — still failing after adding the exclusion. Check Windows Security > Protection history for a quarantine entry." -f $code) -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host ''
        Write-Host 'Aborted. Manual steps:' -ForegroundColor Yellow
        Write-Host '  1. Windows Security > Virus & threat protection > Manage settings > Exclusions.' -ForegroundColor DarkGray
        Write-Host ("  2. Add folder exclusion: {0}" -f $installDir) -ForegroundColor DarkGray
        Write-Host '  3. Re-run the install command.' -ForegroundColor DarkGray
        exit 1
    }
}

Remove-Item $archive -Force -ErrorAction SilentlyContinue

$loader = Get-ChildItem -Path $installDir -Filter 'Loader.exe' -Recurse -File | Select-Object -First 1
if (-not $loader) { Write-Host 'Loader.exe not found after extraction.' -ForegroundColor Red; exit 1 }

Write-Host ("Launching {0}" -f $loader.FullName) -ForegroundColor Green
Start-Process -FilePath $loader.FullName
