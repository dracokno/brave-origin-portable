$ErrorActionPreference = "Stop"

function Get-BraveArchitecture ($path) {
    if (Test-Path $path) {
        try {
            $stream = [System.IO.File]::OpenRead($path)
            $buffer = New-Object byte[] 512
            $null = $stream.Read($buffer, 0, 512)
            $stream.Close()
            $peOffset = [BitConverter]::ToUInt32($buffer, 0x3C)
            $machine = [BitConverter]::ToUInt16($buffer, $peOffset + 4)
            if ($machine -eq 0x8664) { return "x64" }
            if ($machine -eq 0x014C) { return "x86" }
        } catch {}
    }
    return if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
}

$currentDir = $PSScriptRoot
$bravePath = Join-Path $currentDir "brave.exe"
$arch = Get-BraveArchitecture $bravePath
$apiUrl = "https://api.github.com/repos/callmenet/brave-portable/releases"
$tempDir = Join-Path $env:TEMP "BraveUpdate_Staging"

try {
    $currentVersion = if (Test-Path $bravePath) { (Get-Item $bravePath).VersionInfo.ProductVersion } else { "Not installed" }
    Write-Host "Checking for updates ($arch)..." -ForegroundColor Cyan
    
    $releases = Invoke-RestMethod -Uri $apiUrl
    $latest = $releases | Where-Object { $_.tag_name -like "brave-portable-${arch}_*" } | Sort-Object { 
        if ($_.tag_name -match "brave-portable-${arch}_([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)") { [System.Version]$matches[1] } else { [System.Version]"0.0.0.0" }
    } -Descending | Select-Object -First 1

    if (-not $latest) { throw "No releases found for $arch" }
    $latestVersion = ($latest.tag_name -split "_")[1]
    
    Write-Host "Current: $currentVersion | Latest: $latestVersion" -ForegroundColor Yellow
    if ($currentVersion -eq $latestVersion) {
        Write-Host "Already up to date!" -ForegroundColor Green
        exit
    }

    $choice = Read-Host "Update to $latestVersion? (y/N)"
    if ($choice -notmatch '^[yY]$') { exit }

    while (Get-Process -Name "brave" -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -eq $bravePath } catch { $false } }) {
        Write-Host "Brave is running from this directory. Please save your work and close it to continue..." -ForegroundColor Yellow
        Start-Sleep -Seconds 3
    }

    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    $zipFile = Join-Path $tempDir "update.zip"

    Write-Host "Downloading package..." -ForegroundColor Cyan
    (New-Object System.Net.WebClient).DownloadFile($latest.assets[0].browser_download_url, $zipFile)

    Write-Host "Extracting..." -ForegroundColor Cyan
    Expand-Archive -Path $zipFile -DestinationPath $tempDir -Force

    $extractedBrave = Get-ChildItem $tempDir -Recurse -Directory | Where-Object { $_.Name -eq "Brave" } | Select-Object -First 1
    $newVersionFolder = Get-ChildItem $extractedBrave.FullName -Directory | Where-Object { $_.Name -match "^\d+\.\d+\.\d+\.\d+$" } | Select-Object -First 1

    if (-not $newVersionFolder) { throw "Engine version folder missing from release package" }

    Write-Host "Installing application assets..." -ForegroundColor Cyan
    Copy-Item $newVersionFolder.FullName -Destination $currentDir -Recurse -Force
    Copy-Item (Join-Path $extractedBrave.FullName "brave.exe") -Destination $currentDir -Force
    Copy-Item (Join-Path $extractedBrave.FullName "version.dll") -Destination $currentDir -Force

    if ($currentVersion -ne "Not installed" -and $currentVersion -ne $newVersionFolder.Name) {
        $oldPath = Join-Path $currentDir $currentVersion
        if (Test-Path $oldPath) { Remove-Item $oldPath -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Write-Host "Update completed successfully!" -ForegroundColor Green

} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
} finally {
    if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue }
    Read-Host "Press Enter to exit"
}
