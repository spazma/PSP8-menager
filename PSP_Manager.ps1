# ============================================
# AUTO-ELEVACJA + POWRÓT DO KATALOGU SKRYPTU
# ============================================

$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptDir  = Split-Path -Parent $ScriptPath

$IsAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $IsAdmin) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$ScriptPath`""
    exit
}

Set-Location $ScriptDir


# ============================================
# KONFIG
# ============================================

$BackupRoot = Join-Path $ScriptDir "BACKUP"
$TempDir    = Join-Path $env:TEMP "PSP8_RESTORE"
$Date       = (Get-Date).ToString("yyyy-MM-dd_HH-mm")

$ProgramFilesPath = "C:\Program Files (x86)\Jasc Software Inc\Paint Shop Pro 8"


# ============================================
# FUNKCJE POMOCNICZE
# ============================================

function Write-Section($text) {
    Write-Host ""
    Write-Host "=== $text ===" -ForegroundColor Cyan
    Write-Host ""
}

function Pause-Space {
    Write-Host ""
    Write-Host "Press SPACE or ENTER to continue..." -ForegroundColor DarkGray

    while ($true) {
        $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

        if ($key.VirtualKeyCode -eq 13 -or $key.VirtualKeyCode -eq 32) {
            break
        }
    }
}

function Show-Menu {
    Clear-Host
    Write-Host ""
    Write-Host "============================================" -ForegroundColor DarkCyan
    Write-Host "        PSP 8.1 MANAGER - PowerShell" -ForegroundColor Cyan
    Write-Host "============================================" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "1 - Zrob backup" -ForegroundColor Yellow
    Write-Host "2 - Przywroc z ZIP" -ForegroundColor Yellow
    Write-Host "3 - Otworz folder backupow" -ForegroundColor Yellow
    Write-Host "4 - Otworz folder PSP8" -ForegroundColor Yellow
    Write-Host "X - Usun WSZYSTKIE backupy" -ForegroundColor Red
    Write-Host "5 - Wyjdz" -ForegroundColor Gray
    Write-Host ""
}


# ============================================
# BACKUP
# ============================================

function Backup-PSP {

    Write-Section "BACKUP PSP8"

    $OutDir  = Join-Path $BackupRoot "backup_$Date"
    $ZipName = "PSP8_BACKUP_$Date.zip"
    $ZipPath = Join-Path $BackupRoot $ZipName

    New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

    # LIVE PODGL¥D KATALOGÓW
    $folders = @(
        "Brushes",
        "Patterns",
        "Presets",
        "Picture Frames",
        "Textures",
        "Plugins",
        "Gradients",
        "Palettes",
        "Scripts-Restricted",
        "Scripts-Trusted"
    )

    foreach ($f in $folders) {
        $src = Join-Path $ProgramFilesPath $f
        if (Test-Path $src) {
            Write-Host "Kopiuje: $f" -ForegroundColor Green
            Copy-Item -Path $src -Destination (Join-Path $OutDir "ProgramFiles\$f") -Recurse -Force
        }
    }

    # Rejestr
    Write-Host "Eksport rejestru..." -ForegroundColor Green
    $RegOut = Join-Path $OutDir "Registry"
    New-Item -ItemType Directory -Force -Path $RegOut | Out-Null
    reg export "HKEY_CURRENT_USER\Software\Jasc\Paint Shop Pro 8" "$RegOut\PSP8_registry.reg" /y | Out-Null

    # ZIP
    Write-Host "Pakowanie ZIP..." -ForegroundColor Green
    Compress-Archive -Path "$OutDir\*" -DestinationPath $ZipPath -Force

    Remove-Item -Recurse -Force $OutDir

    # Limit 3 kopii
    $zips = Get-ChildItem $BackupRoot -Filter "PSP8_BACKUP_*.zip" | Sort-Object LastWriteTime -Descending
    if ($zips.Count -gt 3) {
        $zips | Select-Object -Skip 3 | Remove-Item -Force
    }

    Write-Host ""
    Write-Host "Backup zapisany jako: $ZipName" -ForegroundColor Cyan
    Pause-Space
}


# ============================================
# RESTORE
# ============================================

function Restore-PSP {

    Write-Section "PRZYWRACANIE PSP8"

    if (-not (Test-Path $BackupRoot)) {
        Write-Host "*** BRAK BACKUPOW ***" -ForegroundColor Red
        Pause-Space
        return
    }

    $zips = Get-ChildItem $BackupRoot -Filter "PSP8_BACKUP_*.zip" | Sort-Object LastWriteTime -Descending

    if ($zips.Count -eq 0) {
        Write-Host "*** BRAK BACKUPOW ***" -ForegroundColor Red
        Pause-Space
        return
    }

    Write-Host "Dostepne backupy:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $zips.Count; $i++) {
        Write-Host "$($i+1) - $($zips[$i].Name)" -ForegroundColor Green
    }

    $choice = Read-Host "Wybierz numer"
    if ($choice -notmatch '^\d+$') { return }
    if ($choice -lt 1 -or $choice -gt $zips.Count) { return }

    $ZipPath = $zips[$choice - 1].FullName

    if (Test-Path $TempDir) { Remove-Item -Recurse -Force $TempDir }
    New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

    Write-Host "Rozpakowywanie ZIP..." -ForegroundColor Green
    Expand-Archive -Path $ZipPath -DestinationPath $TempDir -Force

    # LIVE PODGL¥D RESTORE
    $restoreFolders = Get-ChildItem (Join-Path $TempDir "ProgramFiles") -Directory

    foreach ($f in $restoreFolders) {
        Write-Host "Przywracam: $($f.Name)" -ForegroundColor Green
        Copy-Item -Path $f.FullName -Destination (Join-Path $ProgramFilesPath $f.Name) -Recurse -Force
    }

    Write-Host "Import rejestru..." -ForegroundColor Green
    reg import (Join-Path $TempDir "Registry\PSP8_registry.reg") | Out-Null

    Remove-Item -Recurse -Force $TempDir

    Write-Host ""
    Write-Host "Przywracanie zakonczone." -ForegroundColor Cyan
    Pause-Space
}


# ============================================
# USUWANIE WSZYSTKICH BACKUPÓW
# ============================================

function Delete-All-Backups {

    Write-Section "USUWANIE WSZYSTKICH BACKUPOW"

    if (-not (Test-Path $BackupRoot)) {
        Write-Host "Brak katalogu BACKUP." -ForegroundColor Red
        Pause-Space
        return
    }

    $confirm = Read-Host "Na pewno usunac WSZYSTKO? (T/N)"
    if ($confirm -ne "T") { return }

    Remove-Item -Recurse -Force $BackupRoot
    Write-Host "Wszystkie backupy usuniete." -ForegroundColor Red
    Pause-Space
}


# ============================================
# OTWÓRZ FOLDER BACKUPÓW
# ============================================

function Open-Backup-Folder {

    Write-Section "OTWIERANIE FOLDERU BACKUP"

    if (-not (Test-Path $BackupRoot)) {
        Write-Host "Folder BACKUP nie istnieje — tworze..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null
    }

    Write-Host "Otwieram folder BACKUP..." -ForegroundColor Cyan
    Start-Process $BackupRoot

    Pause-Space
}


# ============================================
# OTWÓRZ FOLDER PSP8
# ============================================

function Open-PSP8-Folder {

    Write-Section "OTWIERANIE FOLDERU PSP8"

    if (-not (Test-Path $ProgramFilesPath)) {
        Write-Host "Folder PSP8 nie istnieje!" -ForegroundColor Red
        Pause-Space
        return
    }

    Write-Host "Otwieram folder PSP8..." -ForegroundColor Cyan
    Start-Process $ProgramFilesPath

    Pause-Space
}


# ============================================
# G£ÓWNA PÊTLA
# ============================================

while ($true) {
    Show-Menu
    $choice = Read-Host "Twoj wybor"

    switch ($choice) {
        "1" { Backup-PSP }
        "2" { Restore-PSP }
        "3" { Open-Backup-Folder }
        "4" { Open-PSP8-Folder }
        "X" { Delete-All-Backups }
        "5" { exit }
    }
}
