[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Target = $null; $TestFile = $null; $SizeMB = 1024; $LogPath = $null; $KeepFile = $false; $ShowHelp = $false

for ($i = 0; $i -lt $args.Count; $i++) {
    switch ([string]$args[$i]) {
        { $_ -in "-h", "--help", "/?" } { $ShowHelp = $true }
        { $_ -in "-k", "--keep" }       { $KeepFile = $true }
        { $_ -in "-f", "--file" }       { $TestFile = [string]$args[++$i] }
        { $_ -in "-s", "--size" }       { $SizeMB = [int]$args[++$i] }
        { $_ -in "-l", "--log" }        { $LogPath = [string]$args[++$i] }
        default { if (-not $_.StartsWith("-")) { $Target = $_ } }
    }
}

if ($ShowHelp -or ([string]::IsNullOrWhiteSpace($Target) -and [string]::IsNullOrWhiteSpace($TestFile))) {
    Write-Host "`nDisk Speed Test (No Admin Required, Unbuffered I/O)`n" -ForegroundColor Cyan
    Write-Host "Usage:" -ForegroundColor Yellow
    Write-Host "  .\test_ssd.ps1 <DriveOrDir> [-s | --size <MB>] [-k | --keep] [-l | --log <LogPath>]"
    Write-Host "  .\test_ssd.ps1 -f | --file <PathToExistingFile> [-l | --log <LogPath>]`n"
    Write-Host "Parameters:" -ForegroundColor Yellow
    Write-Host "  <DriveOrDir>    Target drive letter (D:) or folder path (default: script folder if -f not set)"
    Write-Host "  -s, --size      Size in MB for random file (default: 1024 MB)"
    Write-Host "  -f, --file      Path to existing file for read-only benchmark"
    Write-Host "  -k, --keep      Do not delete generated test file after benchmark"
    Write-Host "  -l, --log       Append results to CSV file`n"
    Write-Host "Examples:" -ForegroundColor Yellow
    Write-Host "  .\test_ssd.ps1 d: -s 2048 --keep"
    Write-Host '  .\test_ssd.ps1 -f "D:\speedtest_2048mb.tmp"'
    return
}

if (-not ([System.Management.Automation.PSTypeName]'DiskUnbufferedV4').Type) {
    Add-Type @"
using System; using System.IO; using System.Runtime.InteropServices; using Microsoft.Win32.SafeHandles;
public class DiskUnbufferedV4 {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFile(string p, uint a, uint s, IntPtr sec, uint c, uint f, IntPtr t);
    public static FileStream OpenRead(string path, int buf) {
        var h = CreateFile(path, 0x80000000, 1, IntPtr.Zero, 3, 0x28000000, IntPtr.Zero);
        if (h.IsInvalid) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        return new FileStream(h, FileAccess.Read, buf, false);
    }
}
"@
}

function Show-Bar([string]$Lbl, [int64]$Cur, [int64]$Tot, [double]$Sec) {
    $pct = [math]::Min(100, [math]::Floor(($Cur / $Tot) * 100))
    $bar = ("#" * [math]::Floor($pct / 5)) + ("-" * (20 - [math]::Floor($pct / 5)))
    $spd = if ($Sec -gt 0.05) { "{0,7:N1} MB/s" -f (($Cur / 1MB) / $Sec) } else { "       --- " }
    $txt = ("{0,-10} [{1}] {2,3}% | {3,5}/{4} MB | {5}" -f $Lbl, $bar, $pct, [math]::Round($Cur/1MB), [math]::Round($Tot/1MB), $spd).PadRight(72)
    try { [Console]::SetCursorPosition(0, [Console]::CursorTop); [Console]::Write($txt) } catch { Write-Host "`r$txt" -NoNewline }
}

function Clear-Bar {
    try { [Console]::SetCursorPosition(0, [Console]::CursorTop); [Console]::Write(" " * 72); [Console]::SetCursorPosition(0, [Console]::CursorTop) } catch {}
}

function Invoke-Generate([int64]$Bytes) {
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $sw = [System.Diagnostics.Stopwatch]::New(); $upd = 0
    $list = [System.Collections.Generic.List[byte[]]]::new()
    [int64]$chunk = 64MB; [int64]$done = 0
    try {
        while ($done -lt $Bytes) {
            $n = [int][Math]::Min($chunk, $Bytes - $done)
            $b = New-Object byte[] ($n)
            $sw.Start(); $rng.GetBytes($b); $sw.Stop()
            $list.Add($b); $done += $n
            if (($sw.ElapsedMilliseconds - $upd) -ge 100) { Show-Bar "Generating" $done $Bytes $sw.Elapsed.TotalSeconds; $upd = $sw.ElapsedMilliseconds }
        }
    } finally { $rng.Dispose(); Clear-Bar }
    return @($sw.Elapsed.TotalSeconds, $list)
}

function Invoke-Write([string]$Path, $Chunks, [int64]$Bytes) {
    $sw = [System.Diagnostics.Stopwatch]::New(); $upd = 0; [int64]$done = 0
    $fs = [System.IO.File]::Create($Path)
    try {
        foreach ($b in $Chunks) {
            $sw.Start(); $fs.Write($b, 0, $b.Length); $sw.Stop()
            $done += $b.Length
            if (($sw.ElapsedMilliseconds - $upd) -ge 100) { Show-Bar "Writing" $done $Bytes $sw.Elapsed.TotalSeconds; $upd = $sw.ElapsedMilliseconds }
        }
        $sw.Start(); $fs.Flush(); $sw.Stop()
    } finally { $fs.Dispose(); Clear-Bar }
    return $sw.Elapsed.TotalSeconds
}

function Invoke-Read([string]$Path) {
    $buf = New-Object byte[] (4MB); $tot = (Get-Item $Path).Length; [int64]$done = 0
    $sw = [System.Diagnostics.Stopwatch]::New(); $upd = 0
    $s = [DiskUnbufferedV4]::OpenRead($Path, 4MB)
    try {
        while ($true) {
            $sw.Start(); $r = $s.Read($buf, 0, $buf.Length); $sw.Stop()
            if ($r -le 0) { break }
            $done += $r
            if (($sw.ElapsedMilliseconds - $upd) -ge 100) { Show-Bar "Reading" $done $tot $sw.Elapsed.TotalSeconds; $upd = $sw.ElapsedMilliseconds }
        }
    } finally { $s.Dispose(); Clear-Bar }
    return $sw.Elapsed.TotalSeconds
}

$isAuto = [string]::IsNullOrWhiteSpace($TestFile)
if (-not $isAuto -and -not (Test-Path $TestFile -PathType Leaf)) { Write-Host "File not found: $TestFile" -ForegroundColor Red; return }

if ($isAuto) {
    if ($Target -match '^[a-zA-Z]:?$') {
        $drv = $Target.TrimEnd(':').ToUpper()
        $workDir = if ($drv -eq "C") { $env:USERPROFILE } else { "${drv}:" }
    } else {
        $workDir = $Target
    }
    if (-not (Test-Path $workDir)) { Write-Host "Path not found: $workDir" -ForegroundColor Red; return }
    $tmp = Join-Path $workDir "speedtest_${SizeMB}mb.tmp"
    [int64]$totalBytes = [int64]$SizeMB * 1MB

    Write-Host "`nBenchmark in $workDir`n$('-' * 58)" -ForegroundColor Cyan
    try {
        $gRes = Invoke-Generate -Bytes $totalBytes
        $genSec = $gRes[0]; $chunks = $gRes[1]
        Write-Host ("{0,-18} {1,10} MB   {2,8:N2} s" -f "1. Data Gen:", $SizeMB, $genSec) -ForegroundColor DarkGray

        $wSec = Invoke-Write -Path $tmp -Chunks $chunks -Bytes $totalBytes
        $chunks.Clear(); [GC]::Collect()
        $wSpd = $SizeMB / $wSec
        Write-Host ("{0,-18} {1,10:N2} MB/s {2,8:N2} s" -f "2. Seq Write:", $wSpd, $wSec) -ForegroundColor Green

        $rSec = Invoke-Read -Path $tmp
        $rSpd = $SizeMB / $rSec
        Write-Host ("{0,-18} {1,10:N2} MB/s {2,8:N2} s`n$('-' * 58)" -f "3. Uncached Read:", $rSpd, $rSec) -ForegroundColor Green

        if ($KeepFile) { Write-Host "Kept file: $tmp" -ForegroundColor Yellow }
        if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
            if (-not (Test-Path $LogPath)) { "Timestamp;Target;Mode;Size_MB;Gen_s;Write_MBs;Write_s;Read_MBs;Read_s" | Out-File $LogPath -Encoding UTF8 }
            "$(Get-Date -f 'yyyy-MM-dd HH:mm:ss');$workDir;Auto;$SizeMB;$([math]::Round($genSec,2));$([math]::Round($wSpd,2));$([math]::Round($wSec,2));$([math]::Round($rSpd,2));$([math]::Round($rSec,2))" | Out-File $LogPath -Append -Encoding UTF8
        }
    } finally {
        if (-not $KeepFile -and (Test-Path $tmp)) { Remove-Item $tmp -Force }
    }
} else {
    $rSize = (Get-Item $TestFile).Length / 1MB
    Write-Host "`nRead Benchmark: $TestFile`n$('-' * 58)" -ForegroundColor Cyan
    $rSec = Invoke-Read -Path $TestFile
    $rSpd = $rSize / $rSec
    Write-Host ("{0,-18} {1,10:N2} MB/s {2,8:N2} s`n$('-' * 58)" -f "Uncached Read:", $rSpd, $rSec) -ForegroundColor Green
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        if (-not (Test-Path $LogPath)) { "Timestamp;Target;Mode;Size_MB;Gen_s;Write_MBs;Write_s;Read_MBs;Read_s" | Out-File $LogPath -Encoding UTF8 }
        "$(Get-Date -f 'yyyy-MM-dd HH:mm:ss');$TestFile;FileOnly;$([math]::Round($rSize,1));0;0;0;$([math]::Round($rSpd,2));$([math]::Round($rSec,2))" | Out-File $LogPath -Append -Encoding UTF8
    }
}
