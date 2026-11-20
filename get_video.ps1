param (
    [Alias('n')]
    [string]$Name,

    [Alias('u')]
    [string]$Url,

    [Alias('f')]
    [string]$File,

    [Alias('d')]
    [string]$dir_dst = (Join-Path $PSScriptRoot "result"),

    [Alias('h', '?')]
    [switch]$Help
)

# 1. Function to display usage instructions and JSON format
function Show-Help {
    Write-Host "`n=== Video Downloader Help ===" -ForegroundColor Cyan
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  1. Download a single video:"
    Write-Host "     .\get_video.ps1 -n `"Video Name`" -u `"https://.../playlist.m3u8`" [-dir_dst `"result`"]" -ForegroundColor Green
    Write-Host "`n  2. Batch download from a JSON file:"
    Write-Host "     .\get_video.ps1 -f `"videos.json`" [-dir_dst `"result`"]" -ForegroundColor Green
    
    Write-Host "`nParameters:" -ForegroundColor Yellow
    Write-Host "  -n, -Name      Output video filename (without .mp4)"
    Write-Host "  -u, -Url       Direct link to .m3u8 playlist"
    Write-Host "  -f, -File      Path to JSON file"
    Write-Host "  -d, -dir_dst   Destination folder for downloaded videos (default: .\result)"
    Write-Host "  -h, -Help      Show this help message"

    Write-Host "`nDirectory Structure:" -ForegroundColor Yellow
    Write-Host "  .\bin\         Must contain yt-dlp.exe, ffmpeg.exe, ffprobe.exe (and .dll files)"
    Write-Host "  .\result\      Default output folder (created automatically)"

    Write-Host "`nJSON File Format Example (UTF-8):" -ForegroundColor Yellow
    Write-Host @"
  [
    {
      "name": "Lecture 1 - Introduction",
      "url": "https://.../playlist.m3u8"
    },
    {
      "name": "Lecture 2 - Logic",
      "url": "https://.../playlist.m3u8"
    }
  ]
"@ -ForegroundColor DarkGray
    Write-Host ""
}

# Helper: Sanitize filename to match Windows & yt-dlp rules
function Get-SafeFileName {
    param (
        [Parameter(Mandatory = $true)]
        [string]$RawName
    )

    $clean = $RawName -replace '\.mp4$', ''
    $clean = $clean -replace '[\\/:*?"<>|]', '_'
    return $clean.Trim()
}

# Helper: Resolve destination directory and create if missing
function Resolve-DestinationDir {
    param (
        [Parameter(Mandatory = $true)]
        [string]$TargetDir
    )

    # If relative path is passed (e.g. "my_videos"), anchor it to script root
    if (-not [System.IO.Path]::IsPathRooted($TargetDir)) {
        $TargetDir = Join-Path $PSScriptRoot $TargetDir
    }

    if (-not (Test-Path $TargetDir)) {
        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
        Write-Host "[Info]: Created destination folder: $TargetDir" -ForegroundColor DarkGray
    }

    return $TargetDir
}

# 2. Function to download a single video (with skip check)
function Invoke-VideoDownload {
    param (
        [Parameter(Mandatory = $true)]
        [string]$VideoName,

        [Parameter(Mandatory = $true)]
        [string]$VideoUrl,

        [Parameter(Mandatory = $true)]
        [string]$OutputDir
    )

    $binDir    = Join-Path $PSScriptRoot "bin"
    $ytDlpPath = Join-Path $binDir "yt-dlp.exe"

    if (-not (Test-Path $ytDlpPath)) {
        Write-Error "yt-dlp.exe not found in '$binDir'. Please place all .exe files inside the 'bin' folder."
        return
    }

    $safeName   = Get-SafeFileName -RawName $VideoName
    $targetFile = Join-Path $OutputDir "$safeName.mp4"

    # Skip if file already exists and is not empty
    if (Test-Path $targetFile) {
        $fileInfo = Get-Item $targetFile
        if ($fileInfo.Length -gt 0) {
            Write-Host "`n[Skipped]:     '$safeName.mp4' already exists in '$OutputDir'." -ForegroundColor DarkYellow
            return
        }
    }

    Write-Host "`n[Downloading]: $safeName" -ForegroundColor Cyan
    Write-Host "[Destination]: $targetFile" -ForegroundColor DarkGray
    Write-Host "[URL]:         $VideoUrl" -ForegroundColor DarkGray

    & $ytDlpPath --ffmpeg-location $binDir --no-overwrites --windows-filenames -o $targetFile $VideoUrl

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[Done]:        $safeName.mp4 saved." -ForegroundColor Green
    } else {
        Write-Warning "[Error]:       Failed to download '$safeName'."
    }
}

# 3. Function to iterate through JSON list
function Invoke-BatchDownload {
    param (
        [Parameter(Mandatory = $true)]
        [string]$JsonPath,

        [Parameter(Mandatory = $true)]
        [string]$OutputDir
    )

    if (-not (Test-Path $JsonPath)) {
        Write-Error "JSON file not found: $JsonPath"
        return
    }

    try {
        $items = Get-Content -Path $JsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-Error "JSON parse error: $_"
        return
    }

    $total = $items.Count
    $current = 0

    Write-Host "Videos found in JSON: $total" -ForegroundColor Yellow

    foreach ($item in $items) {
        $current++
        Write-Host "`n--- Item $current of $total ---" -ForegroundColor Magenta
        
        if ([string]::IsNullOrWhiteSpace($item.name) -or [string]::IsNullOrWhiteSpace($item.url)) {
            Write-Warning "Skipping item #${current}: missing 'name' or 'url'."
            continue
        }

        Invoke-VideoDownload -VideoName $item.name -VideoUrl $item.url -OutputDir $OutputDir
    }
}

# 4. Argument validation and routing
function Start-Downloader {
    # Check if no main action parameters were passed (e.g. only -dir_dst or nothing at all)
    $hasName = -not [string]::IsNullOrWhiteSpace($Name)
    $hasUrl  = -not [string]::IsNullOrWhiteSpace($Url)
    $hasFile = -not [string]::IsNullOrWhiteSpace($File)

    if ($Help -or (-not $hasName -and -not $hasUrl -and -not $hasFile)) {
        Show-Help
        return
    }

    if ($args.Count -gt 0) {
        Write-Host "`n[Error]: Unknown arguments detected: $($args -join ' ')" -ForegroundColor Red
        Show-Help
        return
    }

    if ($hasFile -and ($hasName -or $hasUrl)) {
        Write-Host "`n[Error]: Cannot combine -f (JSON file) with -n or -u." -ForegroundColor Red
        Show-Help
        return
    }

    if (-not $hasFile -and -not ($hasName -and $hasUrl)) {
        Write-Host "`n[Error]: Missing required parameters. Both -n and -u are required for single download." -ForegroundColor Red
        Show-Help
        return
    }

    # Resolve and ensure destination folder exists
    $resolvedDst = Resolve-DestinationDir -TargetDir $dir_dst

    if ($hasFile) {
        Invoke-BatchDownload -JsonPath $File -OutputDir $resolvedDst
        return
    }

    if ($hasName -and $hasUrl) {
        Invoke-VideoDownload -VideoName $Name -VideoUrl $Url -OutputDir $resolvedDst
        return
    }
}

# Entry point
Start-Downloader
