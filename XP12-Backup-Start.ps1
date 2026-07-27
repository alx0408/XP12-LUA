# =====================================================================
#  XP12-Backup - Starter mit Auswahlmenue
# =====================================================================
#  Das ist die Datei, die hinter dem Icon in der Taskleiste liegt.
#  Sie fragt beim Start, was passieren soll, und ruft dann
#  XP12-Backup.ps1 auf. In dieser Datei muss nichts geaendert werden.
# =====================================================================

$ErrorActionPreference = 'Stop'

$backupSkript = Join-Path $PSScriptRoot 'XP12-Backup.ps1'
if (-not (Test-Path -LiteralPath $backupSkript)) {
    Write-Host "FEHLER: XP12-Backup.ps1 wurde nicht gefunden neben dieser Datei." -ForegroundColor Red
    Write-Host "Erwartet in: $PSScriptRoot" -ForegroundColor Red
    Read-Host "`nZum Schliessen Eingabetaste druecken"
    exit 1
}

# Nur auf Windows kann heruntergefahren werden
$aufWindows = -not ($IsMacOS -or $IsLinux)

# ---------------------------------------------------------------------
#  Menue
# ---------------------------------------------------------------------
Clear-Host
Write-Host ""
Write-Host "   ============================================" -ForegroundColor Cyan
Write-Host "     X-PLANE 12  -  BACKUP NACH ONEDRIVE" -ForegroundColor Cyan
Write-Host "   ============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "     [1]  Nur XP-Backup" -ForegroundColor White
Write-Host "     [2]  Backup und Windows herunterfahren" -ForegroundColor White
Write-Host ""
Write-Host "     [3]  Probelauf (zeigt nur an, kopiert nichts)" -ForegroundColor DarkGray
Write-Host "     [0]  Abbrechen" -ForegroundColor DarkGray
Write-Host ""

$wahl = ''
while ($wahl -notin @('0', '1', '2', '3')) {
    $wahl = (Read-Host "   Auswahl").Trim()
    if ($wahl -notin @('0', '1', '2', '3')) {
        Write-Host "   Bitte 0, 1, 2 oder 3 eingeben." -ForegroundColor Yellow
    }
}

if ($wahl -eq '0') {
    Write-Host ""
    Write-Host "   Abgebrochen - es wurde nichts gesichert." -ForegroundColor Yellow
    Write-Host ""
    Start-Sleep -Seconds 2
    exit 0
}

if ($wahl -eq '2' -and -not $aufWindows) {
    Write-Host ""
    Write-Host "   Hinweis: Herunterfahren geht nur unter Windows." -ForegroundColor Yellow
    Write-Host "   Es wird nur das Backup ausgefuehrt." -ForegroundColor Yellow
    Write-Host ""
}

# ---------------------------------------------------------------------
#  Backup ausfuehren
# ---------------------------------------------------------------------
Write-Host ""
if ($wahl -eq '3') {
    & $backupSkript -Probelauf
} else {
    & $backupSkript
}
# 0 = alles gut, 2 = gelaufen, aber einzelne Eintraege fehlten, sonst Fehler
$code = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }

if ($code -eq 2) {
    Write-Host ""
    Write-Host "   Achtung: Einzelne Eintraege der Konfigdatei wurden nicht" -ForegroundColor Yellow
    Write-Host "   gefunden (oben rot markiert). Alles Uebrige ist gesichert." -ForegroundColor Yellow
}
elseif ($code -ne 0) {
    Write-Host ""
    Write-Host "   Das Backup wurde mit einem Fehler beendet." -ForegroundColor Red
    if ($wahl -eq '2') {
        Write-Host "   Es wird NICHT heruntergefahren." -ForegroundColor Red
    }
    Read-Host "`n   Zum Schliessen Eingabetaste druecken"
    exit 1
}

# ---------------------------------------------------------------------
#  Herunterfahren (nur Option 2)
# ---------------------------------------------------------------------
if ($wahl -eq '2' -and $aufWindows) {
    # OneDrive braucht nach dem Kopieren noch Zeit zum Hochladen.
    # Faehrt der PC sofort herunter, liegen die Dateien nur lokal und
    # werden erst beim naechsten Start uebertragen.
    $wartezeit = 90

    Write-Host ""
    Write-Host "   ============================================" -ForegroundColor Cyan
    Write-Host "     OneDrive laedt die Dateien hoch." -ForegroundColor Cyan
    Write-Host "     Danach wird heruntergefahren." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "     Abbruch mit Strg+C" -ForegroundColor DarkGray
    Write-Host "   ============================================" -ForegroundColor Cyan
    Write-Host ""

    for ($i = $wartezeit; $i -gt 0; $i--) {
        Write-Host ("`r     Herunterfahren in {0,3} Sekunden ... " -f $i) -NoNewline -ForegroundColor Yellow
        Start-Sleep -Seconds 1
    }

    Write-Host "`r     Windows wird heruntergefahren.        " -ForegroundColor Yellow
    Write-Host ""
    shutdown.exe /s /t 5 /c "XP12-Backup abgeschlossen"
    exit 0
}

# ---------------------------------------------------------------------
#  Fertig - Fenster offen lassen, damit das Ergebnis lesbar bleibt
# ---------------------------------------------------------------------
Write-Host ""
Read-Host "   Fertig. Zum Schliessen Eingabetaste druecken"
