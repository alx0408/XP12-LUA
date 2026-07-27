# =====================================================================
#  XP12-Backup  -  sichert ausgewaehlte X-Plane-12-Dateien nach OneDrive
# =====================================================================
#  Was gesichert wird, steht ausschliesslich in XP12-Backup-Config.txt.
#  In dieser Datei muss nichts geaendert werden.
#
#  Aufruf:
#     .\XP12-Backup.ps1              normaler Lauf
#     .\XP12-Backup.ps1 -Probelauf   zeigt nur an, was passieren wuerde
# =====================================================================

param(
    [switch]$Probelauf,
    [string]$Konfig
)

$ErrorActionPreference = 'Stop'

# --- Konfigdatei suchen: standardmaessig neben diesem Skript ----------
if (-not $Konfig) {
    $Konfig = Join-Path $PSScriptRoot 'XP12-Backup-Config.txt'
}
if (-not (Test-Path -LiteralPath $Konfig)) {
    Write-Host "FEHLER: Konfigdatei nicht gefunden: $Konfig" -ForegroundColor Red
    exit 1
}

# --- Laeuft das hier auf Windows oder auf dem Mac? -------------------
# In Windows PowerShell 5.1 gibt es $IsMacOS nicht -> dann ist es Windows.
$aufWindows = -not ($IsMacOS -or $IsLinux)
$system     = if ($aufWindows) { 'WINDOWS' } else { 'MAC' }
$trenner    = [IO.Path]::DirectorySeparatorChar

# ---------------------------------------------------------------------
#  Konfigdatei einlesen
# ---------------------------------------------------------------------
$einstellungen = @{}
$eintraege     = @()   # Abschnitt [SICHERN]  -> in den Zeitstempel-Ordner
$spiegel       = @()   # Abschnitt [SPIEGELN] -> in _Spiegel, nur bei Aenderung
$abschnitt     = 'EINSTELLUNGEN'

foreach ($zeile in (Get-Content -LiteralPath $Konfig -Encoding UTF8)) {
    $z = $zeile.Trim()
    if ($z -eq '' -or $z.StartsWith('#')) { continue }

    if ($z -match '^\[SICHERN\]$')  { $abschnitt = 'SICHERN';  continue }
    if ($z -match '^\[SPIEGELN\]$') { $abschnitt = 'SPIEGELN'; continue }

    if ($abschnitt -eq 'EINSTELLUNGEN') {
        # Einstellungszeile:  SCHLUESSEL = Wert
        if ($z -match '^([A-Za-z_]+)\s*=\s*(.*)$') {
            $einstellungen[$matches[1].ToUpper()] = $matches[2].Trim()
        }
        continue
    }

    # Listenzeile:  Pfad  oder  Pfad | Filter1, Filter2
    $teile  = $z -split '\|', 2
    $pfad   = $teile[0].Trim()
    $filter = if ($teile.Count -gt 1) {
                  ($teile[1] -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
              } else { @() }

    if ($pfad) {
        # \ und / vereinheitlichen, damit dieselbe Konfig auf PC und Mac passt
        $normal = $pfad.Replace('\', $trenner).Replace('/', $trenner).TrimStart($trenner)
        $eintrag = [pscustomobject]@{
            Pfad   = $normal
            Filter = $filter
            Roh    = $pfad
        }
        if ($abschnitt -eq 'SPIEGELN') { $spiegel += $eintrag } else { $eintraege += $eintrag }
    }
}

# --- Die zum System passenden Pfade auswaehlen -----------------------
$xpRoot     = $einstellungen["XPLANE_ROOT_$system"]
$backupRoot = $einstellungen["BACKUP_ROOT_$system"]

# Steht in der Konfig AUTO, wird der OneDrive-Ordner bei Windows
# selbst ermittelt - dann muss dort kein Pfad eingetragen werden.
if ($backupRoot -eq 'AUTO') {
    $oneDrive = if ($env:OneDrive) { $env:OneDrive } else { $env:OneDriveConsumer }
    if (-not $oneDrive) {
        Write-Host "FEHLER: OneDrive-Ordner nicht gefunden. Bitte BACKUP_ROOT_$system in der Konfigdatei eintragen." -ForegroundColor Red
        exit 1
    }
    $backupRoot = Join-Path $oneDrive 'XP12-BACKUP'
}
$behalten   = 10
if ($einstellungen.ContainsKey('BEHALTEN') -and $einstellungen['BEHALTEN'] -match '^\d+$') {
    $behalten = [int]$einstellungen['BEHALTEN']
}

Write-Host ""
Write-Host "===== XP12-Backup =====" -ForegroundColor Cyan
Write-Host "System        : $system"
Write-Host "X-Plane-Ordner: $xpRoot"
Write-Host "Backup-Ziel   : $backupRoot"
Write-Host "Eintraege     : $($eintraege.Count) sichern, $($spiegel.Count) spiegeln"
if ($Probelauf) { Write-Host "MODUS         : PROBELAUF - es wird nichts kopiert" -ForegroundColor Yellow }
Write-Host ""

# --- Vorpruefungen ---------------------------------------------------
if (-not $xpRoot -or -not $backupRoot) {
    Write-Host "FEHLER: XPLANE_ROOT_$system oder BACKUP_ROOT_$system fehlt in der Konfigdatei." -ForegroundColor Red
    exit 1
}
if (-not (Test-Path -LiteralPath $xpRoot)) {
    Write-Host "FEHLER: X-Plane-Ordner existiert nicht: $xpRoot" -ForegroundColor Red
    exit 1
}
if ($eintraege.Count -eq 0 -and $spiegel.Count -eq 0) {
    Write-Host "FEHLER: In der Konfigdatei ist weder unter [SICHERN] noch unter [SPIEGELN] etwas eingetragen." -ForegroundColor Red
    exit 1
}

# --- Zielordner mit Zeitstempel --------------------------------------
$stempel = Get-Date -Format 'yyyy-MM-dd_HH-mm'
$ziel    = Join-Path $backupRoot $stempel

if (-not $Probelauf) {
    New-Item -ItemType Directory -Path $ziel -Force | Out-Null
}

# ---------------------------------------------------------------------
#  Kopieren
# ---------------------------------------------------------------------
$protokoll   = @()
$anzDateien  = 0
$anzBytes    = 0
$anzFehler   = 0

function Schreibe-Log([string]$text) {
    $script:protokoll += $text
}

Schreibe-Log "XP12-Backup  $stempel"
Schreibe-Log "System      : $system"
Schreibe-Log "Quelle      : $xpRoot"
Schreibe-Log "Ziel        : $ziel"
Schreibe-Log ""

foreach ($e in $eintraege) {
    $quelle = Join-Path $xpRoot $e.Pfad

    if (-not (Test-Path -LiteralPath $quelle)) {
        Write-Host "  FEHLT   $($e.Roh)" -ForegroundColor Red
        Schreibe-Log "FEHLT    $($e.Roh)"
        $anzFehler++
        continue
    }

    $istOrdner = (Get-Item -LiteralPath $quelle).PSIsContainer

    # Liste der zu kopierenden Dateien ermitteln
    if ($istOrdner) {
        $dateien = @(Get-ChildItem -LiteralPath $quelle -Recurse -File)
        if ($e.Filter.Count -gt 0) {
            $muster  = $e.Filter
            $dateien = @($dateien | Where-Object {
                $n = $_.Name
                @($muster | Where-Object { $n -like $_ }).Count -gt 0
            })
        }
    } else {
        $dateien = @(Get-Item -LiteralPath $quelle)
    }

    if ($dateien.Count -eq 0) {
        Write-Host "  LEER    $($e.Roh)" -ForegroundColor Yellow
        Schreibe-Log "LEER     $($e.Roh)"
        continue
    }

    foreach ($d in $dateien) {
        # Pfad relativ zum X-Plane-Hauptordner -> gleiche Struktur im Backup
        $relativ  = $d.FullName.Substring($xpRoot.TrimEnd($trenner).Length).TrimStart($trenner)
        $zielDatei = Join-Path $ziel $relativ

        if (-not $Probelauf) {
            $zielOrdner = Split-Path -Parent $zielDatei
            if (-not (Test-Path -LiteralPath $zielOrdner)) {
                New-Item -ItemType Directory -Path $zielOrdner -Force | Out-Null
            }
            Copy-Item -LiteralPath $d.FullName -Destination $zielDatei -Force
        }

        $anzDateien++
        $anzBytes += $d.Length
        Schreibe-Log "OK       $relativ"
    }

    $mb = [math]::Round((($dateien | Measure-Object Length -Sum).Sum / 1MB), 2)
    Write-Host ("  OK      {0}  ({1} Datei(en), {2} MB)" -f $e.Roh, $dateien.Count, $mb) -ForegroundColor Green

    # -----------------------------------------------------------------
    #  Kontrolle fuer den Aircraft-Ordner:
    #  Jeder Ordner mit einer .acf-Datei ist ein Flugzeug. Hier wird
    #  geprueft, ob zu JEDEM Flugzeug auch eine Datei gefunden wurde -
    #  damit kein Flugzeug unbemerkt durchrutscht.
    # -----------------------------------------------------------------
    if ($istOrdner -and $e.Filter.Count -gt 0 -and $e.Pfad -match '^Aircraft') {
        $ohneTreffer = @()
        foreach ($acf in (Get-ChildItem -LiteralPath $quelle -Recurse -File -Filter '*.acf')) {
            $flugzeugOrdner = $acf.DirectoryName
            $hatTreffer = $dateien | Where-Object { $_.DirectoryName -eq $flugzeugOrdner }
            if (-not $hatTreffer) {
                $name = $flugzeugOrdner.Substring($xpRoot.TrimEnd($trenner).Length).TrimStart($trenner)
                if ($ohneTreffer -notcontains $name) { $ohneTreffer += $name }
            }
        }

        if ($ohneTreffer.Count -gt 0) {
            Write-Host ("          Hinweis: {0} Flugzeug(e) ohne passende Datei:" -f $ohneTreffer.Count) -ForegroundColor Yellow
            foreach ($o in $ohneTreffer) {
                Write-Host "            - $o" -ForegroundColor Yellow
                Schreibe-Log "OHNE TREFFER  $o"
            }
        } else {
            Write-Host "          Kontrolle: alle Flugzeuge erfasst" -ForegroundColor DarkGray
            Schreibe-Log "KONTROLLE  alle Flugzeuge erfasst"
        }
    }
}

# ---------------------------------------------------------------------
#  SPIEGELN
# ---------------------------------------------------------------------
#  Fuer grosse Ordner, die sich selten aendern (z.B. situations).
#  Sie liegen EINMAL unter _Spiegel und werden nicht bei jedem Lauf
#  neu kopiert - nur neue und geaenderte Dateien werden uebertragen.
#  Es wird nie etwas geloescht: Dateien, die es in X-Plane nicht mehr
#  gibt, bleiben im Spiegel erhalten und werden nur gemeldet.
# ---------------------------------------------------------------------
$spiegelWurzel = Join-Path $backupRoot '_Spiegel'
$spNeu = 0; $spGeaendert = 0; $spGleich = 0; $spVerwaist = 0; $spBytes = 0

if ($spiegel.Count -gt 0) {
    Write-Host ""
    Write-Host "  --- Spiegel (nur Aenderungen) ---" -ForegroundColor Cyan
    Schreibe-Log ""
    Schreibe-Log "--- SPIEGEL ---"
}

foreach ($e in $spiegel) {
    $quelle = Join-Path $xpRoot $e.Pfad

    if (-not (Test-Path -LiteralPath $quelle)) {
        Write-Host "  FEHLT   $($e.Roh)" -ForegroundColor Red
        Schreibe-Log "FEHLT    $($e.Roh)"
        $anzFehler++
        continue
    }

    if ((Get-Item -LiteralPath $quelle).PSIsContainer) {
        $dateien = @(Get-ChildItem -LiteralPath $quelle -Recurse -File)
        if ($e.Filter.Count -gt 0) {
            $muster  = $e.Filter
            $dateien = @($dateien | Where-Object {
                $n = $_.Name
                @($muster | Where-Object { $n -like $_ }).Count -gt 0
            })
        }
    } else {
        $dateien = @(Get-Item -LiteralPath $quelle)
    }

    $eNeu = 0; $eGeaendert = 0; $eGleich = 0

    foreach ($d in $dateien) {
        $relativ    = $d.FullName.Substring($xpRoot.TrimEnd($trenner).Length).TrimStart($trenner)
        $zielDatei  = Join-Path $spiegelWurzel $relativ
        $vorhanden  = Test-Path -LiteralPath $zielDatei

        # Unveraendert = gleiche Groesse UND gleiche Aenderungszeit
        $istGleich = $false
        if ($vorhanden) {
            $alt = Get-Item -LiteralPath $zielDatei
            $istGleich = ($alt.Length -eq $d.Length) -and
                         ([math]::Abs(($alt.LastWriteTime - $d.LastWriteTime).TotalSeconds) -lt 2)
        }

        if ($istGleich) {
            $eGleich++
            continue
        }

        if (-not $Probelauf) {
            $zielOrdner = Split-Path -Parent $zielDatei
            if (-not (Test-Path -LiteralPath $zielOrdner)) {
                New-Item -ItemType Directory -Path $zielOrdner -Force | Out-Null
            }
            Copy-Item -LiteralPath $d.FullName -Destination $zielDatei -Force
        }

        $spBytes += $d.Length
        if ($vorhanden) { $eGeaendert++; Schreibe-Log "GEAENDERT $relativ" }
        else            { $eNeu++;       Schreibe-Log "NEU       $relativ" }
    }

    # Dateien im Spiegel, die es in X-Plane nicht mehr gibt - nur melden
    $eVerwaist = @()
    $spiegelOrdner = Join-Path $spiegelWurzel $e.Pfad
    if (Test-Path -LiteralPath $spiegelOrdner) {
        $quellNamen = @{}
        foreach ($d in $dateien) { $quellNamen[$d.FullName] = $true }
        foreach ($alt in (Get-ChildItem -LiteralPath $spiegelOrdner -Recurse -File)) {
            $relativ = $alt.FullName.Substring($spiegelWurzel.TrimEnd($trenner).Length).TrimStart($trenner)
            if (-not $quellNamen.ContainsKey((Join-Path $xpRoot $relativ))) {
                $eVerwaist += $relativ
            }
        }
    }

    $spNeu += $eNeu; $spGeaendert += $eGeaendert; $spGleich += $eGleich
    $spVerwaist += $eVerwaist.Count

    $farbe = if ($eNeu + $eGeaendert -gt 0) { 'Green' } else { 'DarkGray' }
    Write-Host ("  OK      {0}  ({1} neu, {2} geaendert, {3} unveraendert)" -f `
                $e.Roh, $eNeu, $eGeaendert, $eGleich) -ForegroundColor $farbe

    if ($eVerwaist.Count -gt 0) {
        Write-Host ("          Hinweis: {0} Datei(en) nur noch im Spiegel (in X-Plane geloescht):" -f $eVerwaist.Count) -ForegroundColor Yellow
        foreach ($v in $eVerwaist) {
            Write-Host "            - $v" -ForegroundColor Yellow
            Schreibe-Log "NUR IM SPIEGEL  $v"
        }
    }
}

# ---------------------------------------------------------------------
#  Alte Backup-Staende aufraeumen
# ---------------------------------------------------------------------
$geloescht = 0
if (-not $Probelauf -and $behalten -gt 0) {
    $alle = Get-ChildItem -LiteralPath $backupRoot -Directory |
            Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}$' } |
            Sort-Object Name -Descending

    if ($alle.Count -gt $behalten) {
        foreach ($alt in $alle[$behalten..($alle.Count - 1)]) {
            Remove-Item -LiteralPath $alt.FullName -Recurse -Force
            Schreibe-Log "GELOESCHT (alter Stand)  $($alt.Name)"
            $geloescht++
        }
    }
}

# ---------------------------------------------------------------------
#  Zusammenfassung + Protokoll
# ---------------------------------------------------------------------
$mbGesamt = [math]::Round(($anzBytes / 1MB), 2)

$mbSpiegel = [math]::Round(($spBytes / 1MB), 2)

Schreibe-Log ""
Schreibe-Log "Gesichert   : $anzDateien Datei(en), $mbGesamt MB"
Schreibe-Log "Spiegel     : $spNeu neu, $spGeaendert geaendert, $spGleich unveraendert ($mbSpiegel MB uebertragen)"
Schreibe-Log "Fehlend     : $anzFehler Eintrag/Eintraege"
Schreibe-Log "Aufgeraeumt : $geloescht alte(r) Stand/Staende"

Write-Host ""
Write-Host "Gesichert : $anzDateien Datei(en), $mbGesamt MB" -ForegroundColor Cyan
if ($spiegel.Count -gt 0) {
    Write-Host "Spiegel   : $spNeu neu, $spGeaendert geaendert, $spGleich unveraendert -> $mbSpiegel MB uebertragen" -ForegroundColor Cyan
}
if ($anzFehler -gt 0) {
    Write-Host "Fehlend   : $anzFehler Eintrag/Eintraege (siehe oben, rot)" -ForegroundColor Red
}
if ($geloescht -gt 0) {
    Write-Host "Aufgeraeumt: $geloescht alte(r) Backup-Stand/-Staende geloescht"
}

if (-not $Probelauf) {
    $protokoll | Set-Content -LiteralPath (Join-Path $ziel '_Protokoll.txt') -Encoding UTF8
    Write-Host "Ziel      : $ziel" -ForegroundColor Cyan
}
Write-Host ""

# Rueckmeldung an den Aufrufer: 0 = alles gut, 2 = einzelne Eintraege fehlten
if ($anzFehler -gt 0) { exit 2 }
exit 0
