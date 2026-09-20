# =====================================================================
#  Legt eine Verknuepfung "XP12 Backup" auf dem Desktop an
# =====================================================================
#  NICHT direkt starten, sondern ueber XP12-Backup-Einrichten.cmd
#  (Doppelklick). Die .cmd sorgt dafuer, dass Windows das Skript
#  ausfuehren darf und das Fenster offen bleibt.
# =====================================================================

if ($IsMacOS -or $IsLinux) {
    Write-Host "  Diese Datei funktioniert nur unter Windows." -ForegroundColor Yellow
    exit 1
}

$fehler = $false

try {
    $startSkript = Join-Path $PSScriptRoot 'XP12-Backup-Start.ps1'

    if (-not (Test-Path -LiteralPath $startSkript)) {
        throw "XP12-Backup-Start.ps1 liegt nicht neben dieser Datei.`n  Erwartet in: $PSScriptRoot"
    }

    # Ziel ist powershell.exe, nicht die .cmd: Batch-Dateien laesst
    # Windows nicht an die Taskleiste anheften. "-ExecutionPolicy Bypass"
    # umgeht die Ausfuehrungssperre genauso wie die .cmd.
    $ziel      = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $argumente = "-NoProfile -ExecutionPolicy Bypass -File `"$startSkript`""

    $desktop = [Environment]::GetFolderPath('DesktopDirectory')
    if (-not $desktop -or -not (Test-Path -LiteralPath $desktop)) {
        throw "Desktop-Ordner nicht gefunden."
    }

    $linkPfad = Join-Path $desktop 'XP12 Backup.lnk'

    $shell = New-Object -ComObject WScript.Shell
    $link  = $shell.CreateShortcut($linkPfad)
    $link.TargetPath       = $ziel
    $link.Arguments        = $argumente
    $link.WorkingDirectory = $PSScriptRoot
    $link.Description      = "X-Plane 12 Dateien nach OneDrive sichern"
    $link.IconLocation     = "$env:SystemRoot\System32\imageres.dll,54"
    $link.Save()

    if (-not (Test-Path -LiteralPath $linkPfad)) {
        throw "Die Verknuepfung wurde nicht angelegt: $linkPfad"
    }

    Write-Host ""
    Write-Host "  Verknuepfung angelegt." -ForegroundColor Green
    Write-Host ""
    Write-Host "  Ort   : $linkPfad"
    Write-Host "  Zeigt auf: $ziel"
    Write-Host ""
    Write-Host "  Naechster Schritt:" -ForegroundColor Cyan
    Write-Host "  Rechtsklick auf die Verknuepfung -> An Taskleiste anheften"
    Write-Host ""
    Write-Host "  Der Ordner wird jetzt geoeffnet, die Datei ist markiert."

    Start-Process explorer.exe "/select,`"$linkPfad`""
}
catch {
    $fehler = $true
    Write-Host ""
    Write-Host "  FEHLER: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Bitte diese Meldung melden." -ForegroundColor Yellow
}

if ($fehler) { exit 1 }
exit 0
