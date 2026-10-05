#Requires -Version 7
[CmdletBinding()]
param()

# Black-Box-Test für share/tools/wt.ps1 gegen share/arbeitsbaeume.md (Abschnitte 6–7) und den
# Implementierungsvertrag. Arbeitet nur in einem Wegwerf-Repo unter $env:TEMP und prüft je Fall
# Exitcode, letzte Zeile „WT: <STATUS> …“ und den Git-Zustand danach. Einige Fälle starten
# Hilfsprozesse (Sperre halten, Ordner belegen, Dateien zu einem bestimmten Zeitpunkt schreiben, ein
# Programm aus dem Worktree, wt im Hintergrund); das Ende räumt sie ab. Junctions zeigen nur auf
# Kanarienordner innerhalb der Testwurzel.

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$wtSkript = Join-Path (Split-Path -Parent $PSScriptRoot) 'share\tools\wt.ps1'
if (-not (Test-Path -LiteralPath $wtSkript -PathType Leaf)) {
    throw "wt.ps1 fehlt: $wtSkript"
}
$pwshExe = (Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source
if (-not $pwshExe) { $pwshExe = [Environment]::ProcessPath }
$utf8 = [Text.UTF8Encoding]::new($false)

$tempPrefix = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$testPath = [IO.Path]::GetFullPath((Join-Path $env:TEMP ('wt smoke ' + [guid]::NewGuid().ToString('N').Substring(0, 8))))

function Test-Testziel([string]$Pfad) {
    $Pfad.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and
        ([IO.Path]::GetFileName($Pfad) -cmatch '^wt smoke [0-9a-f]{8}$')
}
if (-not (Test-Testziel $testPath)) {
    throw 'Unzulässiges Testziel'
}

# Projektwerte des Wegwerf-Repos; einzelne Fälle committen Abwandlungen und stellen danach wieder her.
# sperreWartenMinuten kurz, damit ein Sperrfehler den Test nicht stundenlang aufhält.
$konfigBasis = [ordered]@{
    gate                = 'pwsh -NoProfile -File gate.ps1'
    issueOrdner         = @('issues')
    nurAufMain          = @('projektplan.md')
    gateIrrelevant      = @('docs/notizen/')
    nummernPruefung     = @([ordered]@{ ordner = 'docs/adr'; muster = '^ADR-(\d{4})-' })
    sperreWartenMinuten = 1
}

# Gitignorierte Pflichtdateien laut .worktreeinclude (Ordner zuerst, dann zwei Dateien) mit Inhalt.
$envInhalt = "GEHEIM=smoke-123`n"
$pflichtDateien = [ordered]@{
    '.env.local'                  = $envInhalt
    '.lokal\daten.txt'            = "lokal 1`n"
    '.lokal\sub\tief.txt'         = "lokal tief`n"
    '.claude\settings.local.json' = "{ `"permissions`": {} }`n"
}

# --- Hilfsfunktionen ---------------------------------------------------------------------------
# Git-Argumente immer als Array übergeben: PowerShell verschluckt beim Binden von Funktionsparametern
# ein freistehendes „--“ und deutet „-o…“ als Parameterpräfix.

function Invoke-Git {
    param([Parameter(Mandatory)][string]$Ort, [Parameter(Mandatory)][string[]]$A, [switch]$DarfScheitern)
    $altEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $roh = @(& git -C $Ort @A 2>&1)
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $altEap
    }
    $aus = [Collections.Generic.List[string]]::new()
    $err = [Collections.Generic.List[string]]::new()
    foreach ($eintrag in $roh) {
        $zeile = "$eintrag".TrimEnd()
        if (-not $zeile.Trim()) { continue }
        if ($eintrag -is [Management.Automation.ErrorRecord]) { $err.Add($zeile) } else { $aus.Add($zeile) }
    }
    if ($code -ne 0 -and -not $DarfScheitern) {
        throw "git $($A -join ' ') in '$Ort' scheiterte (Exit $code): $((@($aus) + @($err)) -join ' | ')"
    }
    [pscustomobject]@{ Code = $code; Aus = $aus.ToArray(); Err = $err.ToArray() }
}

function Get-GitZeilen([string]$Ort, [string[]]$A) {
    (Invoke-Git -Ort $Ort -A $A).Aus
}

function Get-GitWert([string]$Ort, [string[]]$A) {
    $aus = @((Invoke-Git -Ort $Ort -A $A).Aus)
    if ($aus.Count) { $aus[0].Trim() } else { '' }
}

function Test-Git([string]$Ort, [string[]]$A) {
    (Invoke-Git -Ort $Ort -A $A -DarfScheitern).Code -eq 0
}

function Get-Sha([string]$Rev, [string]$Ort) {
    if (-not $Ort) { $Ort = $haupt }
    $r = Invoke-Git -Ort $Ort -A @('rev-parse', '--verify', '-q', $Rev) -DarfScheitern
    if ($r.Code -eq 0 -and @($r.Aus).Count) { $r.Aus[0].Trim() } else { '' }
}

function Get-Zweig([string]$Ort) {
    $r = Invoke-Git -Ort $Ort -A @('symbolic-ref', '--short', '-q', 'HEAD') -DarfScheitern
    if ($r.Code -eq 0 -and @($r.Aus).Count) { $r.Aus[0].Trim() } else { '(detached)' }
}

function Get-Aenderungen([string]$Ort) {
    @(Get-GitZeilen $Ort @('status', '--porcelain', '-uall'))
}

function Get-CommitDateien([string]$Ort) {
    @(Get-GitZeilen $Ort @('diff-tree', '--no-commit-id', '--name-only', '-r', 'HEAD'))
}

# Status des letzten Commits je Pfad ohne Umbenennungserkennung, z. B. „D src/alt.txt“.
function Get-CommitStatus([string]$Ort) {
    @(Get-GitZeilen $Ort @('diff-tree', '--no-commit-id', '--name-status', '--no-renames', '-r', 'HEAD') |
        ForEach-Object { $_ -replace '\s+', ' ' })
}

function Test-Vorfahr([string]$Vorfahr, [string]$Nachfahr) {
    Test-Git $haupt @('merge-base', '--is-ancestor', $Vorfahr, $Nachfahr)
}

function Test-Objekt([string]$Spec) {
    Test-Git $haupt @('cat-file', '-e', $Spec)
}

function Test-Zweig([string]$Name) {
    Test-Git $haupt @('show-ref', '--verify', '-q', "refs/heads/$Name")
}

function Test-OffenerVorgang([string]$Wt) {
    $gitDir = Get-GitWert $Wt @('rev-parse', '--path-format=absolute', '--git-dir')
    foreach ($name in 'rebase-merge', 'rebase-apply', 'MERGE_HEAD') {
        if (Test-Path -LiteralPath (Join-Path $gitDir $name)) { return $true }
    }
    $false
}

function Get-WorktreeEintraege {
    @(Get-GitZeilen $haupt @('worktree', 'list', '--porcelain') |
        Where-Object { $_.StartsWith('worktree ') } |
        ForEach-Object { $_.Substring(9) })
}

function Test-Registriert([string]$Pfad) {
    $soll = [IO.Path]::GetFullPath($Pfad).TrimEnd('\', '/')
    foreach ($eintrag in @(Get-WorktreeEintraege)) {
        if ([string]::Equals([IO.Path]::GetFullPath($eintrag).TrimEnd('\', '/'), $soll, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    $false
}

function Test-GateReste {
    $ordner = @(Get-ChildItem -LiteralPath $wtWurzel -Directory -Filter '_gate-*' -ErrorAction SilentlyContinue)
    $eintraege = @(Get-WorktreeEintraege | Where-Object { $_ -match '[\\/]_gate-[^\\/]*$' })
    ($ordner.Count + $eintraege.Count) -gt 0
}

function New-GitCommit([string]$Ort, [string]$Nachricht, [string[]]$Pfade) {
    Get-GitZeilen $Ort (@('add', '--') + $Pfade) | Out-Null
    Get-GitZeilen $Ort (@('commit', '-q', '-m', $Nachricht, '--') + $Pfade) | Out-Null
    Get-Sha 'HEAD' $Ort
}

function Set-Datei([string]$Pfad, [string]$Inhalt) {
    $ordner = Split-Path -Parent $Pfad
    if (-not (Test-Path -LiteralPath $ordner)) {
        New-Item -ItemType Directory -Force -Path $ordner | Out-Null
    }
    [IO.File]::WriteAllText($Pfad, $Inhalt)
}

function Read-Text([string]$Pfad) {
    [IO.File]::ReadAllText($Pfad)
}

function Test-Menge($Ist, [string[]]$Soll) {
    $liste = @($Ist | Where-Object { $null -ne $_ } | ForEach-Object { "$_" })
    if ($liste.Count -ne $Soll.Count) { return $false }
    foreach ($eintrag in $Soll) {
        if ($liste -cnotcontains $eintrag) { return $false }
    }
    $true
}

function Get-Zaehler {
    if (Test-Path -LiteralPath $zaehlerDatei) { [int](Read-Text $zaehlerDatei).Trim() } else { 0 }
}

function Get-Nachweis([string]$Tree, [string]$Fall) {
    $pfad = Join-Path $gatesDir "$Tree.ok"
    if (-not $Tree -or -not (Test-Path -LiteralPath $pfad)) { return $null }
    try {
        Get-Content -LiteralPath $pfad -Raw | ConvertFrom-Json
    } catch {
        throw "Fall ${Fall}: Gate-Nachweis ist kein gültiges JSON: $pfad"
    }
}

# Fehlende oder abweichende Pflichtdateien (.worktreeinclude) in einem Worktree.
function Get-PflichtFehler([string]$Wt) {
    foreach ($rel in $pflichtDateien.Keys) {
        $kopie = Join-Path $Wt $rel
        if (-not (Test-Path -LiteralPath $kopie -PathType Leaf) -or (Read-Text $kopie) -cne $pflichtDateien[$rel]) { $rel }
    }
}

# Dateien unter einem Ordner als „relativer Pfad|Größe“, sortiert – erkennt Löschen und Verändern.
function Get-DateiStand([string]$Ordner) {
    @(Get-ChildItem -LiteralPath $Ordner -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
            '{0}|{1}' -f [IO.Path]::GetRelativePath($Ordner, $_.FullName).Replace('\', '/'), $_.Length
        } | Sort-Object)
}

function New-KonfigText([Collections.IDictionary]$Aenderungen = @{}) {
    $k = [ordered]@{}
    foreach ($n in $konfigBasis.Keys) { $k[$n] = $konfigBasis[$n] }
    foreach ($n in $Aenderungen.Keys) { $k[$n] = $Aenderungen[$n] }
    (($k | ConvertTo-Json -Depth 5) -replace "`r`n", "`n") + "`n"
}

# Die Projektwerte gelten aus HEAD des Hauptcheckouts; Abwandlungen werden deshalb committet (am Werkzeug
# vorbei, nur wenn HEAD noch einen anderen Stand hat).
function Set-KonfigCommit([string]$Text, [string]$Nachricht) {
    Set-Datei $konfigPfad $Text
    if ((Get-GitBlob $haupt 'HEAD:.ai-sdlc/arbeitsbaeume.json') -cne $Text) {
        Get-GitZeilen $haupt @('commit', '-q', '-m', $Nachricht, '--', '.ai-sdlc/arbeitsbaeume.json') | Out-Null
    }
}

function Wait-Datei([string]$Pfad, [double]$Sekunden) {
    $uhr = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath $Pfad)) {
        if ($uhr.Elapsed.TotalSeconds -ge $Sekunden) { return $false }
        Start-Sleep -Milliseconds 100
    }
    $true
}

# Merkt sich einen Prozess, dessen PID ein Hilfsskript in eine Datei geschrieben hat. Das offene
# Handle verhindert, dass die PID bis zum Aufräumen an einen fremden Prozess vergeben wird.
function Add-ProzessAusDatei([string]$Pfad) {
    try {
        $p = [Diagnostics.Process]::GetProcessById([int](Read-Text $Pfad).Trim())
        [void]$p.Handle
        $script:Prozesse.Add($p)
        $p
    } catch {
        $null
    }
}

function Add-ProzessNachPid([int]$Id) {
    try {
        $p = [Diagnostics.Process]::GetProcessById($Id)
        [void]$p.Handle
        $script:Prozesse.Add($p)
        $p
    } catch {
        $null
    }
}

function Stop-Restprozesse {
    foreach ($frei in $script:FreiMarken) {
        try { if (-not (Test-Path -LiteralPath $frei)) { [IO.File]::WriteAllText($frei, 'frei') } } catch { }
    }
    foreach ($p in $script:Prozesse) {
        try {
            if (-not $p.HasExited -and -not $p.WaitForExit(5000)) { $p.Kill($true) }
        } catch { }
    }
}

# Hilfsprozess mit Arbeitsverzeichnis $Ort; hält optional $Datei offen (None: exklusiv wie eine
# wt-Sperre, Read: andere dürfen lesen, aber nicht schreiben oder löschen). Läuft bis Stop-Halter.
function Start-Halter {
    param([Parameter(Mandatory)][string]$Ort, [string]$Datei = '', [ValidateSet('None', 'Read')][string]$Teilen = 'None')
    $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $bereit = Join-Path $testPath "halter-$id.bereit"
    $frei = Join-Path $testPath "halter-$id.frei"
    $script:FreiMarken.Add($frei)
    $psi = [Diagnostics.ProcessStartInfo]::new($pwshExe)
    $argumente = @('-NoProfile', '-File', $halterSkript, '-Bereit', $bereit, '-Frei', $frei, '-Teilen', $Teilen)
    if ($Datei) { $argumente += @('-Datei', $Datei) }
    foreach ($x in $argumente) { $psi.ArgumentList.Add($x) }
    $psi.WorkingDirectory = $Ort
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    $script:Prozesse.Add($p)
    if (-not (Wait-Datei $bereit 30)) {
        throw "Hilfsprozess (PID $($p.Id), Arbeitsverzeichnis $Ort) meldet sich nicht bereit"
    }
    [pscustomobject]@{ P = $p; Frei = $frei }
}

function Stop-Halter($Halter) {
    if ($null -eq $Halter) { return }
    if (-not (Test-Path -LiteralPath $Halter.Frei)) { [IO.File]::WriteAllText($Halter.Frei, 'frei') }
    if (-not $Halter.P.WaitForExit(30000)) {
        try { $Halter.P.Kill($true) } catch { }
    }
}

# Schreiber-Hilfsprozess (schreiber.ps1): NachGate schreibt eine Datei, sobald ein neuer temporärer
# Gate-Worktree verschwunden ist; Flut legt ab einem Startsignal laufend neue Dateien an. -Werte ergänzt
# die Parameter (Wurzel, Datei, Text bzw. Start, Ordner).
function Start-Schreiber {
    param([Parameter(Mandatory)][ValidateSet('NachGate', 'Flut')][string]$Modus, [Collections.IDictionary]$Werte = @{})
    $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $bereit = Join-Path $testPath "schreiber-$id.bereit"
    $ergebnis = Join-Path $testPath "schreiber-$id.ergebnis"
    $stopp = Join-Path $testPath "schreiber-$id.stopp"
    $script:FreiMarken.Add($stopp)
    $psi = [Diagnostics.ProcessStartInfo]::new($pwshExe)
    $argumente = @('-NoProfile', '-File', $schreiberSkript, '-Modus', $Modus, '-Bereit', $bereit, '-Ergebnis', $ergebnis, '-Stopp', $stopp)
    foreach ($n in $Werte.Keys) { $argumente += @("-$n", [string]$Werte[$n]) }
    foreach ($x in $argumente) { $psi.ArgumentList.Add($x) }
    $psi.WorkingDirectory = $testPath
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    $script:Prozesse.Add($p)
    if (-not (Wait-Datei $bereit 30)) {
        throw "Schreiber (PID $($p.Id), Modus $Modus) meldet sich nicht bereit"
    }
    [pscustomobject]@{ P = $p; Ergebnis = $ergebnis; Stopp = $stopp }
}

# Wartet auf das Ende des Schreibers (sonst Stopp-Signal) und liefert seine Ergebniszeile.
function Complete-Schreiber($S, [double]$Sekunden = 15) {
    if (-not $S.P.WaitForExit([int]($Sekunden * 1000))) {
        [IO.File]::WriteAllText($S.Stopp, 'stopp')
        if (-not $S.P.WaitForExit(15000)) { try { $S.P.Kill($true) } catch { } }
    }
    if (Test-Path -LiteralPath $S.Ergebnis) { (Read-Text $S.Ergebnis).Trim() } else { '' }
}

# Programm (z. B. Kopie von ping.exe) mit Arbeitsverzeichnis außerhalb der Worktrees; Ausgabe wird verworfen.
function Start-Programm([string]$Exe, [string[]]$Argumente) {
    $psi = [Diagnostics.ProcessStartInfo]::new($Exe)
    foreach ($x in $Argumente) { $psi.ArgumentList.Add($x) }
    $psi.WorkingDirectory = $testPath
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $p = [Diagnostics.Process]::Start($psi)
    $script:Prozesse.Add($p)
    [void]$p.StandardOutput.ReadToEndAsync()
    [void]$p.StandardError.ReadToEndAsync()
    $p
}

# Beendet das Programm und wartet, bis seine Programmdatei nicht mehr geladen ist (exklusiv zu öffnen).
function Stop-Programm($P, [string]$Exe) {
    try { if (-not $P.HasExited) { $P.Kill($true) } } catch { }
    [void]$P.WaitForExit(15000)
    $uhr = [Diagnostics.Stopwatch]::StartNew()
    while ((Test-Path -LiteralPath $Exe) -and $uhr.Elapsed.TotalSeconds -lt 15) {
        try {
            $fs = [IO.File]::Open($Exe, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            $fs.Dispose()
            return
        } catch {
            Start-Sleep -Milliseconds 100
        }
    }
}

# Kanarienordner unter der Testwurzel als Ziel von Junctions; Stand = Dateien mit Größe.
function New-Kanarie([string]$Name) {
    $pfad = Join-Path $testPath $Name
    Set-Datei (Join-Path $pfad 'kanarie.txt') "fremde Daten ($Name)`n"
    Set-Datei (Join-Path $pfad 'sub\kanarie2.txt') "fremde Daten 2 ($Name)`n"
    [pscustomobject]@{ Pfad = $pfad; Name = $Name; Stand = ((Get-DateiStand $pfad) -join "`n") }
}

function Test-Kanarie($K) {
    (Test-Path -LiteralPath $K.Pfad -PathType Container) -and ((Get-DateiStand $K.Pfad) -join "`n") -ceq $K.Stand
}

function New-Junction([string]$Pfad, [string]$Ziel) {
    $ordner = Split-Path -Parent $Pfad
    if (-not (Test-Path -LiteralPath $ordner)) { New-Item -ItemType Directory -Force -Path $ordner | Out-Null }
    New-Item -ItemType Junction -Path $Pfad -Target $Ziel | Out-Null
    if (-not ((Get-Item -LiteralPath $Pfad -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Vorbereitung gescheitert – $Pfad ist keine Junction"
    }
}

# Exakter Inhalt eines Blobs (z. B. HEAD:src/c.txt) ohne Zeilenaufbereitung; $null, wenn er fehlt.
function Get-GitBlob([string]$Ort, [string]$Spec) {
    $psi = [Diagnostics.ProcessStartInfo]::new('git')
    foreach ($x in @('-C', $Ort, 'cat-file', 'blob', $Spec)) { $psi.ArgumentList.Add($x) }
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $utf8
    $p = [Diagnostics.Process]::Start($psi)
    try {
        $fehler = $p.StandardError.ReadToEndAsync()
        $text = $p.StandardOutput.ReadToEnd()
        $p.WaitForExit()
        [void]$fehler.Wait(5000)
        if ($p.ExitCode -ne 0) { return $null }
        $text
    } finally {
        $p.Dispose()
    }
}

# Stellt die Standard-Projektwerte in Arbeitskopie und HEAD wieder her, falls ein Fall sie abgewandelt hat.
function Reset-Konfig([string]$Nachricht) {
    Set-KonfigCommit $konfigText $Nachricht
}

# Wert einer Ausgabezeile „NAME=wert“ (z. B. WORKTREE=); $null, wenn sie fehlt oder mehrfach vorkommt.
function Get-AusgabeWert($Ergebnis, [string]$Name) {
    $muster = '^\s*' + [regex]::Escape($Name) + '='
    $treffer = @($Ergebnis.Text -split "`n" | Where-Object { $_ -cmatch $muster })
    if ($treffer.Count -ne 1) { return $null }
    ($treffer[0] -creplace $muster, '').Trim()
}

function Test-GleicherPfad([string]$A, [string]$B) {
    if (-not $A -or -not $B) { return $false }
    [string]::Equals([IO.Path]::GetFullPath($A).TrimEnd('\', '/'), [IO.Path]::GetFullPath($B).TrimEnd('\', '/'),
        [StringComparison]::OrdinalIgnoreCase)
}

function New-WtErgebnis($Alle, $Aus, $Err, $Code, [string]$Befehl) {
    # stdout und stderr kommen getrennt an; die WT-Zeile muss die letzte Zeile ihres Datenstroms sein.
    $wtZeile = $null
    foreach ($strom in @($Aus, $Err)) {
        $liste = @($strom | Where-Object { $null -ne $_ })
        if ($liste.Count -and $liste[$liste.Count - 1] -cmatch '^WT: ') {
            $wtZeile = $liste[$liste.Count - 1]
            break
        }
    }
    $status = if ($wtZeile -and $wtZeile -cmatch '^WT: (\S+)') { $Matches[1] } else { $null }
    [pscustomobject]@{
        Code    = $Code
        Text    = @($Alle) -join "`n"
        WtZeile = $wtZeile
        Status  = $status
        Befehl  = $Befehl
    }
}

function Invoke-Wt {
    param([Parameter(Mandatory)][string]$Ort, [Parameter(Mandatory)][string[]]$A)
    $altEap = $ErrorActionPreference
    # wt schreibt UTF-8; so kommen Umlaute in Meldungen unverfälscht an.
    $altKodierung = $null
    try { $altKodierung = [Console]::OutputEncoding; [Console]::OutputEncoding = $utf8 } catch { $altKodierung = $null }
    Push-Location -LiteralPath $Ort
    try {
        $ErrorActionPreference = 'Continue'
        $roh = @(& $pwshExe -NoProfile -File $wtSkript @A 2>&1)
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $altEap
        Pop-Location
        if ($null -ne $altKodierung) { try { [Console]::OutputEncoding = $altKodierung } catch { } }
    }
    $alle = [Collections.Generic.List[string]]::new()
    $aus = [Collections.Generic.List[string]]::new()
    $err = [Collections.Generic.List[string]]::new()
    foreach ($eintrag in $roh) {
        $zeile = ("$eintrag" -replace "`e\[[0-9;?]*[ -/]*[@-~]", '').TrimEnd()
        $alle.Add($zeile)
        if (-not $zeile.Trim()) { continue }
        if ($eintrag -is [Management.Automation.ErrorRecord]) { $err.Add($zeile.Trim()) } else { $aus.Add($zeile.Trim()) }
    }
    New-WtErgebnis $alle $aus $err $code ($A -join ' ')
}

# wt als eigener Prozess; stdout lässt sich zeilenweise mitlesen (Wait-WtZeile).
function Start-WtHintergrund {
    param([Parameter(Mandatory)][string]$Ort, [Parameter(Mandatory)][string[]]$A)
    $psi = [Diagnostics.ProcessStartInfo]::new($pwshExe)
    foreach ($x in @('-NoProfile', '-File', $wtSkript) + $A) { $psi.ArgumentList.Add($x) }
    $psi.WorkingDirectory = $Ort
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $utf8
    $psi.StandardErrorEncoding = $utf8
    $p = [Diagnostics.Process]::Start($psi)
    $script:Prozesse.Add($p)
    [pscustomobject]@{
        P      = $p
        Befehl = $A -join ' '
        Zeilen = [Collections.Generic.List[string]]::new()
        Offen  = $null
        Fehler = $p.StandardError.ReadToEndAsync()
    }
}

function Wait-WtZeile($H, [string]$Muster, [double]$Sekunden) {
    $uhr = [Diagnostics.Stopwatch]::StartNew()
    while ($uhr.Elapsed.TotalSeconds -lt $Sekunden) {
        if ($null -eq $H.Offen) { $H.Offen = $H.P.StandardOutput.ReadLineAsync() }
        if (-not $H.Offen.Wait(250)) { continue }
        $zeile = $H.Offen.Result
        $H.Offen = $null
        if ($null -eq $zeile) { return $false }
        $H.Zeilen.Add($zeile)
        if ($zeile -match $Muster) { return $true }
    }
    $false
}

function Complete-WtHintergrund($H, [int]$Sekunden = 180) {
    if (-not $H.P.WaitForExit($Sekunden * 1000)) {
        throw "wt $($H.Befehl) im Hintergrund endete nicht innerhalb von $Sekunden s"
    }
    # Den Rest nur befristet lesen: ein Enkelprozess kann die geerbte Pipe noch offen halten.
    $rest = ''
    $lesbar = $true
    if ($null -ne $H.Offen) {
        if ($H.Offen.Wait(10000)) {
            if ($null -ne $H.Offen.Result) { $H.Zeilen.Add($H.Offen.Result) }
            $H.Offen = $null
        } else {
            $lesbar = $false
        }
    }
    if ($lesbar) {
        $t = $H.P.StandardOutput.ReadToEndAsync()
        if ($t.Wait(10000)) { $rest = $t.Result }
    }
    $fehlerText = if ($H.Fehler.Wait(10000)) { $H.Fehler.Result } else { '' }
    $alle = [Collections.Generic.List[string]]::new()
    $aus = [Collections.Generic.List[string]]::new()
    $err = [Collections.Generic.List[string]]::new()
    foreach ($z in @($H.Zeilen) + @($rest -split "`r?`n")) {
        $zeile = ("$z" -replace "`e\[[0-9;?]*[ -/]*[@-~]", '').TrimEnd()
        $alle.Add($zeile)
        if ($zeile.Trim()) { $aus.Add($zeile.Trim()) }
    }
    foreach ($z in @($fehlerText -split "`r?`n")) {
        $zeile = ("$z" -replace "`e\[[0-9;?]*[ -/]*[@-~]", '').TrimEnd()
        if (-not $zeile.Trim()) { continue }
        $alle.Add($zeile)
        $err.Add($zeile.Trim())
    }
    New-WtErgebnis $alle $aus $err $H.P.ExitCode $H.Befehl
}

# Gibt es eine Ausgabezeile, auf die alle Muster (Regex) zutreffen?
function Test-Zeile($Ergebnis, [string[]]$Muster) {
    foreach ($zeile in @($Ergebnis.Text -split "`n")) {
        $treffer = $true
        foreach ($m in $Muster) {
            if ($zeile -notmatch $m) { $treffer = $false; break }
        }
        if ($treffer) { return $true }
    }
    $false
}

function Test-PfadInText([string]$Text, [string]$Pfad) {
    $voll = [IO.Path]::GetFullPath($Pfad).TrimEnd('\', '/')
    foreach ($variante in @($voll, $voll.Replace('\', '/'))) {
        if ($Text.IndexOf($variante, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    $false
}

function Format-Ausgabe($Ergebnis) {
    if (-not $Ergebnis) { return '' }
    $zeilen = @($Ergebnis.Text -split "`n")
    if ($zeilen.Count -gt 60) { $zeilen = $zeilen[-60..-1] }
    "`n--- wt $($Ergebnis.Befehl) (Exit $($Ergebnis.Code)) ---`n" + ($zeilen -join "`n")
}

function Assert-Bedingung($Bedingung, [string]$Fall, [string]$Text, $Ergebnis = $null) {
    if (-not $Bedingung) {
        throw "Fall ${Fall}: $Text$(Format-Ausgabe $Ergebnis)"
    }
}

function Assert-Wt($Ergebnis, [int]$Code, [string]$Status, [string]$Fall) {
    Assert-Bedingung ($Ergebnis.Code -eq $Code -and $Ergebnis.Status -ceq $Status) $Fall `
        "erwartet Exit $Code mit 'WT: $Status', erhalten Exit $($Ergebnis.Code) mit '$($Ergebnis.WtZeile)'" $Ergebnis
}

# --- Testlauf ----------------------------------------------------------------------------------

$envNamen = @('GIT_CONFIG_GLOBAL', 'WT_SMOKE_ZAEHLER', 'WT_SMOKE_HAUPT', 'WT_SMOKE_MARKE', 'WT_SMOKE_BEWEGEN',
    'WT_SMOKE_AENDERN', 'WT_SMOKE_LAEUFT', 'WT_SMOKE_HALTEN', 'WT_SMOKE_DAEMON', 'WT_SMOKE_ENDE', 'WT_SMOKE_KANARIE')
$envAlt = @{}
foreach ($name in $envNamen) { $envAlt[$name] = [Environment]::GetEnvironmentVariable($name) }
$script:Prozesse = [Collections.Generic.List[Diagnostics.Process]]::new()
$script:FreiMarken = [Collections.Generic.List[string]]::new()

try {
    New-Item -ItemType Directory -Path $testPath | Out-Null
    $haupt = Join-Path $testPath 'haupt repo'
    $wtWurzel = Join-Path $haupt '.claude\worktrees'
    $konfigPfad = Join-Path $haupt '.ai-sdlc\arbeitsbaeume.json'
    $konfigText = New-KonfigText
    $zaehlerDatei = Join-Path $testPath 'gate-zaehler.txt'
    $marke = Join-Path $testPath 'main-bewegt.marke'
    $halterSkript = Join-Path $testPath 'halter.ps1'
    $schreiberSkript = Join-Path $testPath 'schreiber.ps1'
    $globaleConfig = Join-Path $testPath 'gitconfig-global'
    [IO.File]::WriteAllText($globaleConfig, '')
    # Persönliche Git-Einstellungen (Editor, Signatur, autoStash …) dürfen das Ergebnis nicht beeinflussen.
    $env:GIT_CONFIG_GLOBAL = $globaleConfig
    $env:WT_SMOKE_ZAEHLER = $zaehlerDatei
    $env:WT_SMOKE_HAUPT = $haupt
    $env:WT_SMOKE_MARKE = $marke
    foreach ($name in 'WT_SMOKE_BEWEGEN', 'WT_SMOKE_AENDERN', 'WT_SMOKE_LAEUFT', 'WT_SMOKE_HALTEN', 'WT_SMOKE_DAEMON',
        'WT_SMOKE_ENDE', 'WT_SMOKE_KANARIE') {
        [Environment]::SetEnvironmentVariable($name, $null)
    }

    Write-Output 'Vorbereitung: Wegwerf-Repo anlegen'
    # Das Gate zählt seine Läufe in einer Datei außerhalb des Repos, prüft die Pflichtdateien, wird durch
    # eine Datei ROT im Baum rot und kann auf Wunsch (Umgebungsvariablen) main bewegen, eine genannte
    # Datei im Hauptcheckout ändern, auf Freigabe warten, einen erbenden Hintergrundprozess starten oder
    # sein Ende in einer Datei melden.
    $gateSkript = @'
# Smoke-Gate fuer tests/wt-smoke.ps1
$ErrorActionPreference = 'Stop'
$zaehler = $env:WT_SMOKE_ZAEHLER
if (-not $zaehler) { Write-Output 'GATE-FEHLT: WT_SMOKE_ZAEHLER'; exit 3 }
$lauf = 1
if (Test-Path -LiteralPath $zaehler) { $lauf = [int]([IO.File]::ReadAllText($zaehler).Trim()) + 1 }
[IO.File]::WriteAllText($zaehler, [string]$lauf)
Write-Output "GATE: Lauf $lauf in $PSScriptRoot"
foreach ($pflicht in '.env.local', '.lokal/daten.txt', '.lokal/sub/tief.txt', '.claude/settings.local.json') {
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot $pflicht) -PathType Leaf)) { Write-Output "GATE-FEHLT: $pflicht"; exit 4 }
}
if ($env:WT_SMOKE_LAEUFT) {
    # meldet sich und wartet auf Freigabe, damit der Test wt waehrend des Gates beenden kann
    [IO.File]::WriteAllText($env:WT_SMOKE_LAEUFT, [string]$PID)
    $uhr = [Diagnostics.Stopwatch]::StartNew()
    while (-not (Test-Path -LiteralPath $env:WT_SMOKE_HALTEN) -and $uhr.Elapsed.TotalSeconds -lt 150) { Start-Sleep -Milliseconds 100 }
    Write-Output 'GATE: freigegeben'
}
if ($env:WT_SMOKE_AENDERN) {
    # aendert waehrend des Gates eine genannte Datei im Hauptcheckout
    [IO.File]::WriteAllText((Join-Path $env:WT_SMOKE_HAUPT $env:WT_SMOKE_AENDERN), "waehrend des Gates geaendert`n")
    Write-Output "GATE: $env:WT_SMOKE_AENDERN im Hauptcheckout geaendert"
}
if ($env:WT_SMOKE_DAEMON) {
    # Hintergrundprozess, der die Ausgabe des Gates erbt und das Gate ueberlebt
    $psi = [Diagnostics.ProcessStartInfo]::new([Environment]::ProcessPath)
    foreach ($x in '-NoProfile', '-Command', 'Start-Sleep -Seconds 45') { $psi.ArgumentList.Add($x) }
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = Split-Path -Parent $zaehler
    $d = [Diagnostics.Process]::Start($psi)
    [IO.File]::WriteAllText($env:WT_SMOKE_DAEMON, [string]$d.Id)
    Write-Output "GATE: Hintergrundprozess $($d.Id) gestartet"
}
$modus = $env:WT_SMOKE_BEWEGEN
if ($modus -and -not (Test-Path -LiteralPath $env:WT_SMOKE_MARKE)) {
    [IO.File]::WriteAllText($env:WT_SMOKE_MARKE, $modus)
    $datei = if ($modus -eq 'irrelevant') { 'docs/notizen/x.md' } else { 'src/b.txt' }
    $voll = Join-Path $env:WT_SMOKE_HAUPT $datei
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $voll) | Out-Null
    [IO.File]::WriteAllText($voll, "main bewegt sich ($modus, Lauf $lauf)`n")
    git -C $env:WT_SMOKE_HAUPT add -- $datei
    if ($LASTEXITCODE -ne 0) { Write-Output 'GATE-FEHLT: git add'; exit 5 }
    git -C $env:WT_SMOKE_HAUPT commit -q -m "main bewegt sich ($modus)" -- $datei
    if ($LASTEXITCODE -ne 0) { Write-Output 'GATE-FEHLT: git commit'; exit 5 }
    Write-Output "GATE: main bewegt ($datei)"
}
if ($env:WT_SMOKE_ENDE) {
    # meldet das Ende des Gates (Startsignal fuer einen Schreiber des Tests)
    [IO.File]::WriteAllText($env:WT_SMOKE_ENDE, [string]$lauf)
}
if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'ROT')) { Write-Output 'GATE-ROT: Datei ROT im Baum'; exit 1 }
Write-Output 'GATE: gruen'
exit 0
'@
    $halterInhalt = @'
# Hilfsprozess fuer tests/wt-smoke.ps1: haelt optional eine Datei offen und laeuft im vom Test
# vorgegebenen Arbeitsverzeichnis, bis die Freigabe-Datei existiert.
param([string]$Datei, [Parameter(Mandatory)][string]$Bereit, [Parameter(Mandatory)][string]$Frei,
    [ValidateSet('None', 'Read')][string]$Teilen = 'None', [int]$MaxSekunden = 150)
$ErrorActionPreference = 'Stop'
$strom = $null
if ($Datei) {
    if ($Teilen -eq 'Read') {
        $strom = [IO.File]::Open($Datei, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    } else {
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Datei))
        $strom = [IO.File]::Open($Datei, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    }
}
[IO.File]::WriteAllText($Bereit, [string]$PID)
$uhr = [Diagnostics.Stopwatch]::StartNew()
while (-not (Test-Path -LiteralPath $Frei) -and $uhr.Elapsed.TotalSeconds -lt $MaxSekunden) { Start-Sleep -Milliseconds 100 }
if ($null -ne $strom) { $strom.Dispose() }
'@
    Set-Datei $halterSkript ($halterInhalt -replace "`r`n", "`n")
    $schreiberInhalt = @'
# Hilfsprozess fuer tests/wt-smoke.ps1: aendert Dateien im Hauptcheckout zu einem vom Test bestimmten Zeitpunkt.
# NachGate: wartet auf einen neuen temporaeren Gate-Worktree (_gate-*) unter -Wurzel und auf sein Verschwinden,
#           schreibt dann sofort -Text in -Datei.
# Flut:     legt ab dem Startsignal (Datei -Start) alle 4 ms eine neue Datei unter -Ordner an, bis -Stopp existiert.
param([Parameter(Mandatory)][ValidateSet('NachGate', 'Flut')][string]$Modus, [Parameter(Mandatory)][string]$Bereit,
    [Parameter(Mandatory)][string]$Ergebnis, [Parameter(Mandatory)][string]$Stopp, [string]$Wurzel, [string]$Datei,
    [string]$Text, [string]$Start, [string]$Ordner, [int]$MaxSekunden = 150)
$ErrorActionPreference = 'Stop'
$uhr = [Diagnostics.Stopwatch]::StartNew()
function Test-Weiter { -not (Test-Path -LiteralPath $Stopp) -and $uhr.Elapsed.TotalSeconds -lt $MaxSekunden }
if ($Modus -eq 'NachGate') {
    $vorher = @(Get-ChildItem -LiteralPath $Wurzel -Directory -Filter '_gate-*' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    [IO.File]::WriteAllText($Bereit, [string]$PID)
    $gate = $null
    while (-not $gate -and (Test-Weiter)) {
        $gate = @(Get-ChildItem -LiteralPath $Wurzel -Directory -Filter '_gate-*' -ErrorAction SilentlyContinue |
                Where-Object { $vorher -notcontains $_.Name } | Select-Object -First 1)[0]
        if (-not $gate) { Start-Sleep -Milliseconds 2 }
    }
    if (-not $gate) { [IO.File]::WriteAllText($Ergebnis, 'kein temporaerer Gate-Worktree gesehen'); exit 2 }
    while ([IO.Directory]::Exists($gate.FullName) -and (Test-Weiter)) { Start-Sleep -Milliseconds 1 }
    if ([IO.Directory]::Exists($gate.FullName)) { [IO.File]::WriteAllText($Ergebnis, "Gate-Worktree blieb: $($gate.Name)"); exit 3 }
    [IO.File]::WriteAllText($Datei, "$Text`n")
    [IO.File]::WriteAllText($Ergebnis, 'geschrieben')
    exit 0
}
[IO.File]::WriteAllText($Bereit, [string]$PID)
while (-not (Test-Path -LiteralPath $Start) -and (Test-Weiter)) { Start-Sleep -Milliseconds 5 }
if (-not (Test-Path -LiteralPath $Start)) { [IO.File]::WriteAllText($Ergebnis, '0'); exit 2 }
[void][IO.Directory]::CreateDirectory($Ordner)
$n = 0
$takt = [Diagnostics.Stopwatch]::StartNew()
while ((Test-Weiter) -and $n -lt 5000) {
    [IO.File]::WriteAllText((Join-Path $Ordner "entwurf-$n.tmp"), "entwurf $n`n")
    $n++
    $ziel = $takt.Elapsed.TotalMilliseconds + 4
    while ($takt.Elapsed.TotalMilliseconds -lt $ziel) { }
}
[IO.File]::WriteAllText($Ergebnis, [string]$n)
exit 0
'@
    Set-Datei $schreiberSkript ($schreiberInhalt -replace "`r`n", "`n")
    New-Item -ItemType Directory -Path $haupt | Out-Null
    Get-GitZeilen $haupt @('init', '-q', '-b', 'main') | Out-Null
    Get-GitZeilen $haupt @('config', 'user.name', 'WT Smoke') | Out-Null
    Get-GitZeilen $haupt @('config', 'user.email', 'wt-smoke@example.invalid') | Out-Null
    Get-GitZeilen $haupt @('config', 'core.autocrlf', 'false') | Out-Null
    Set-Datei (Join-Path $haupt 'projektplan.md') "# Projektplan`n`n- IS-001 Demo`n"
    Set-Datei (Join-Path $haupt 'issues\IS-001-demo\impl-plan.md') "# Impl-Plan IS-001`n`n- [ ] Schritt 1`n- [ ] Schritt 2`n"
    Set-Datei (Join-Path $haupt 'issues\IS-002-zweites\issue.md') "# IS-002`n`nFreigabe: offen`n"
    Set-Datei (Join-Path $haupt 'src\a.txt') "zeile 1`nzeile 2`nzeile 3`nzeile 4`nzeile 5`n"
    Set-Datei (Join-Path $haupt 'src\c.txt') "c 1`nc 2`nc 3`n"
    Set-Datei (Join-Path $haupt 'docs\adr\ADR-0001-start.md') "# ADR-0001 Start`n"
    Set-Datei (Join-Path $haupt '.gitignore') "/.claude/worktrees/`n.env.local`n.gate-logs/`n.lokal/`n.claude/settings.local.json`n"
    Set-Datei (Join-Path $haupt '.worktreeinclude') "# Pflichtdateien fuer neue Worktrees (Ordner zuerst)`n`n.lokal/`n.env.local`n.claude/settings.local.json`n"
    foreach ($rel in $pflichtDateien.Keys) { Set-Datei (Join-Path $haupt $rel) $pflichtDateien[$rel] }
    Set-Datei $konfigPfad $konfigText
    Set-Datei (Join-Path $haupt 'gate.ps1') ($gateSkript -replace "`r`n", "`n")
    Get-GitZeilen $haupt @('add', '-A') | Out-Null
    Get-GitZeilen $haupt @('commit', '-q', '-m', 'Start') | Out-Null
    foreach ($rel in @('.env.local', '.lokal/daten.txt', '.lokal/sub/tief.txt', '.claude/settings.local.json')) {
        if (@(Get-GitZeilen $haupt @('ls-files', '--', $rel)).Count -ne 0 -or -not (Test-Git $haupt @('check-ignore', '-q', $rel))) {
            throw "Vorbereitung: $rel ist nicht ignoriert"
        }
    }
    $common = Get-GitWert $haupt @('rev-parse', '--path-format=absolute', '--git-common-dir')
    $gatesDir = Join-Path $common 'ai-sdlc\gates'

    Write-Output 'Fall 1: start legt .claude/worktrees/is-001 auf Branch is-001-demo an, kopiert .worktreeinclude (Ordner zuerst, zwei Dateien) und legt die Gate-Ablage an'
    $mainStart = Get-Sha 'main'
    $r = Invoke-Wt $haupt @('start', '-Key', 'IS-001', '-Slug', 'demo')
    Assert-Wt $r 0 'OK' '1'
    $wt1 = Join-Path $wtWurzel 'is-001'
    Assert-Bedingung (Test-Path -LiteralPath (Join-Path $wt1 '.git')) '1' "Worktree fehlt: $wt1" $r
    Assert-Bedingung (@(Get-ChildItem -LiteralPath $wtWurzel -Directory | Where-Object { $_.Name -ceq 'is-001' }).Count -eq 1) '1' `
        'Worktree-Ordner heißt nicht klein geschrieben is-001' $r
    Assert-Bedingung ((Get-Zweig $wt1) -ceq 'is-001-demo') '1' "Worktree steht auf '$(Get-Zweig $wt1)' statt auf is-001-demo" $r
    Assert-Bedingung ((Get-Sha 'HEAD' $wt1) -eq $mainStart) '1' 'Branch zweigt nicht vom lokalen main ab' $r
    $fehlt = @(Get-PflichtFehler $wt1)
    Assert-Bedingung ($fehlt.Count -eq 0) '1' "Pflichtdateien laut .worktreeinclude fehlen oder weichen ab: $($fehlt -join ', ')" $r
    Assert-Bedingung (-not (Test-Path -LiteralPath (Join-Path $wt1 '.lokal\.env.local'))) '1' `
        '.env.local landete im Ordner des vorigen .worktreeinclude-Eintrags (.lokal/)' $r
    Assert-Bedingung ($r.Text.Contains('is-001-demo')) '1' 'Ausgabe nennt den Branch nicht' $r
    Assert-Bedingung (@(Get-Aenderungen $wt1).Count -eq 0) '1' 'Worktree ist nach start nicht sauber' $r
    Assert-Bedingung (@(Get-Aenderungen $haupt).Count -eq 0) '1' 'Hauptcheckout ist nach start nicht sauber' $r
    Assert-Bedingung ((Test-Path -LiteralPath (Join-Path $wt1 '.gate-logs') -PathType Container) -and
        (Test-Git $wt1 @('check-ignore', '-q', '.gate-logs/'))) '1' 'start hat die Gate-Ablage .gate-logs im Worktree nicht (ignoriert) angelegt' $r

    Write-Output 'Fall 2: zweites start verwendet den Worktree wieder und ergänzt fehlende Pflichtdateien, ohne zu überschreiben'
    $einstWt1 = Join-Path $wt1 '.claude\settings.local.json'
    $envWt1 = Join-Path $wt1 '.env.local'
    Remove-Item -LiteralPath $einstWt1
    [IO.File]::WriteAllText($envWt1, "GEHEIM=im-worktree-geaendert`n")
    $kopf = Get-Sha 'HEAD' $wt1
    $anzahl = @(Get-WorktreeEintraege).Count
    $r = Invoke-Wt $haupt @('start', '-Key', 'IS-001')
    Assert-Wt $r 0 'OK' '2'
    Assert-Bedingung (@(Get-WorktreeEintraege).Count -eq $anzahl) '2' 'start hat einen weiteren Worktree angelegt' $r
    Assert-Bedingung ((Get-Zweig $wt1) -ceq 'is-001-demo' -and (Get-Sha 'HEAD' $wt1) -eq $kopf) '2' `
        'Wiederverwendeter Worktree hat Branch oder Stand gewechselt' $r
    Assert-Bedingung ((Test-Path -LiteralPath $einstWt1) -and (Read-Text $einstWt1) -ceq $pflichtDateien['.claude\settings.local.json']) '2' `
        'Die fehlende Pflichtdatei .claude/settings.local.json wurde beim Wiederverwenden nicht nachkopiert' $r
    Assert-Bedingung ((Read-Text $envWt1) -ceq "GEHEIM=im-worktree-geaendert`n") '2' `
        'start hat die vorhandene .env.local im Worktree überschrieben' $r
    [IO.File]::WriteAllText($envWt1, $envInhalt)

    Write-Output 'Fall 3: start verweigert bei uncommitteter Änderung im Issue-Ordner des Hauptcheckouts (anlegen und wiederverwenden)'
    $issue2 = Join-Path $haupt 'issues\IS-002-zweites\issue.md'
    $issue2Alt = Read-Text $issue2
    $issue2Neu = $issue2Alt + "Freigabe: erteilt`n"
    [IO.File]::WriteAllText($issue2, $issue2Neu)
    $r = Invoke-Wt $haupt @('start', '-Key', 'IS-002', '-Slug', 'zweites')
    Assert-Wt $r 12 'BLOCKIERT' '3'
    Assert-Bedingung (-not (Test-Path -LiteralPath (Join-Path $wtWurzel 'is-002'))) '3' 'Worktree is-002 wurde trotzdem angelegt' $r
    Assert-Bedingung (@(Get-GitZeilen $haupt @('branch', '--list', 'is-002*')).Count -eq 0) '3' 'Branch für IS-002 wurde trotzdem angelegt' $r
    Assert-Bedingung ((Read-Text $issue2) -ceq $issue2Neu) '3' 'Die uncommittete Änderung im Issue-Ordner wurde verändert' $r
    [IO.File]::WriteAllText($issue2, $issue2Alt)
    $plan1Haupt = Join-Path $haupt 'issues\IS-001-demo\impl-plan.md'
    $plan1Alt = Read-Text $plan1Haupt
    $plan1Neu = $plan1Alt + "- [ ] Schritt 3 (Neufreigabe)`n"
    [IO.File]::WriteAllText($plan1Haupt, $plan1Neu)
    $kopf = Get-Sha 'HEAD' $wt1
    $r = Invoke-Wt $haupt @('start', '-Key', 'IS-001')
    Assert-Wt $r 12 'BLOCKIERT' '3'
    Assert-Bedingung ((Get-Sha 'HEAD' $wt1) -eq $kopf -and (Get-Zweig $wt1) -ceq 'is-001-demo') '3' `
        'Der vorhandene Worktree wurde trotz Blockade verändert' $r
    Assert-Bedingung ((Read-Text $plan1Haupt) -ceq $plan1Neu) '3' 'Die uncommittete Neufreigabe im Hauptcheckout wurde verändert' $r
    [IO.File]::WriteAllText($plan1Haupt, $plan1Alt)

    Write-Output 'Fall 4: commit im Worktree committet genau die genannte neue und geänderte Datei'
    Set-Datei (Join-Path $wt1 'src\neu1.txt') "neu 1`n"
    $plan1 = Join-Path $wt1 'issues\IS-001-demo\impl-plan.md'
    [IO.File]::WriteAllText($plan1, (Read-Text $plan1).Replace('- [ ] Schritt 1', '- [x] Schritt 1'))
    Set-Datei (Join-Path $wt1 'src\entwurf.txt') "nicht genannt`n"
    [IO.File]::AppendAllText((Join-Path $wt1 'src\c.txt'), "nicht genannt`n")
    $kopf = Get-Sha 'HEAD' $wt1
    $r = Invoke-Wt $wt1 @('commit', '-Nachricht', 'IS-001: Einheit 1', 'src/neu1.txt', 'issues/IS-001-demo/impl-plan.md')
    Assert-Wt $r 0 'OK' '4'
    Assert-Bedingung ((Get-Sha 'HEAD~1' $wt1) -eq $kopf -and (Get-Zweig $wt1) -ceq 'is-001-demo') '4' `
        'Es entstand nicht genau ein Commit auf is-001-demo' $r
    $dateien = @(Get-CommitDateien $wt1)
    Assert-Bedingung (Test-Menge $dateien @('src/neu1.txt', 'issues/IS-001-demo/impl-plan.md')) '4' "Commit enthält: $($dateien -join ', ')" $r
    Assert-Bedingung ((Get-GitWert $wt1 @('log', '-1', '--format=%s')) -ceq 'IS-001: Einheit 1') '4' 'Commit-Nachricht stimmt nicht' $r
    $rest = @(Get-Aenderungen $wt1)
    Assert-Bedingung (Test-Menge $rest @(' M src/c.txt', '?? src/entwurf.txt')) '4' `
        "Nicht genannte Änderungen wurden angefasst: $($rest -join ', ')" $r
    Get-GitZeilen $wt1 @('checkout', '-q', '--', 'src/c.txt') | Out-Null
    Remove-Item -LiteralPath (Join-Path $wt1 'src\entwurf.txt')

    Write-Output 'Fall 5: commit im Hauptcheckout lässt eine fremd gestagte Datei gestagt und unverändert'
    $fremd = Join-Path $haupt 'docs\fremd.txt'
    Set-Datei $fremd "gestagt`n"
    Get-GitZeilen $haupt @('add', '--', 'docs/fremd.txt') | Out-Null
    [IO.File]::WriteAllText($fremd, "danach geaendert`n")
    $indexAlt = Get-GitWert $haupt @('ls-files', '-s', '--', 'docs/fremd.txt')
    [IO.File]::AppendAllText((Join-Path $haupt 'projektplan.md'), "- IS-002 Zweites`n")
    $kopf = Get-Sha 'HEAD'
    $r = Invoke-Wt $haupt @('commit', '-Nachricht', 'IS-001: Projektplan ergaenzt', 'projektplan.md')
    Assert-Wt $r 0 'OK' '5'
    Assert-Bedingung ((Get-Sha 'HEAD~1') -eq $kopf -and (Get-Zweig $haupt) -ceq 'main') '5' 'Es entstand nicht genau ein Commit auf main' $r
    $dateien = @(Get-CommitDateien $haupt)
    Assert-Bedingung (Test-Menge $dateien @('projektplan.md')) '5' "Commit enthält: $($dateien -join ', ')" $r
    Assert-Bedingung ((Get-GitWert $haupt @('ls-files', '-s', '--', 'docs/fremd.txt')) -ceq $indexAlt) '5' `
        'Der gestagte Stand der fremden Datei wurde verändert' $r
    Assert-Bedingung ((Read-Text $fremd) -ceq "danach geaendert`n") '5' 'Der Arbeitsbaum-Stand der fremden Datei wurde verändert' $r
    $rest = @(Get-Aenderungen $haupt)
    Assert-Bedingung (Test-Menge $rest @('AM docs/fremd.txt')) '5' "Unerwarteter Status im Hauptcheckout: $($rest -join ', ')" $r
    Get-GitZeilen $haupt @('reset', '-q', '--', 'docs/fremd.txt') | Out-Null
    Remove-Item -LiteralPath $fremd

    Write-Output 'Fall 6: commit ohne Änderung meldet NICHTS'
    $kopf = Get-Sha 'HEAD' $wt1
    $r = Invoke-Wt $wt1 @('commit', '-Nachricht', 'IS-001: leer', 'src/a.txt')
    Assert-Wt $r 14 'NICHTS' '6'
    Assert-Bedingung ((Get-Sha 'HEAD' $wt1) -eq $kopf) '6' 'Trotz NICHTS entstand ein Commit' $r

    Write-Output 'Fall 7: integrate bringt is-001-demo per ff nach main, Gate genau einmal'
    $zaehler = Get-Zaehler
    $mainAlt = Get-Sha 'main'
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-001')
    Assert-Wt $r 0 'OK' '7'
    $mainNeu = Get-Sha 'main'
    Assert-Bedingung ($mainNeu -eq (Get-Sha 'is-001-demo')) '7' 'main steht nicht auf dem Branch-Tip' $r
    Assert-Bedingung ($mainNeu -ne $mainAlt -and (Test-Vorfahr $mainAlt $mainNeu)) '7' 'main wurde nicht vorwärts bewegt' $r
    Assert-Bedingung ((Get-Zaehler) -eq $zaehler + 1) '7' "Gate lief $((Get-Zaehler) - $zaehler)-mal statt einmal" $r
    Assert-Bedingung ((Test-Path -LiteralPath (Join-Path $haupt 'src\neu1.txt')) -and (Get-Zweig $haupt) -ceq 'main' -and
        @(Get-Aenderungen $haupt).Count -eq 0) '7' 'Hauptcheckout steht nicht sauber auf dem neuen main' $r
    $tree = Get-Sha 'main^{tree}'
    $nachweis = Get-Nachweis $tree '7'
    Assert-Bedingung ($nachweis -and $nachweis.tree -eq $tree) '7' "Gate-Nachweis für Tree $tree fehlt" $r
    Assert-Bedingung (@(Get-ChildItem -LiteralPath (Join-Path $wt1 '.gate-logs') -Filter 'wt-gate-*.log' -File -ErrorAction SilentlyContinue).Count -ge 1) '7' `
        'Gate-Log fehlt unter .gate-logs im Worktree' $r

    Write-Output 'Fall 8: integrate ohne neue Commits (im Worktree, ohne -Key) meldet NICHTS'
    $zaehler = Get-Zaehler
    $mainAlt = Get-Sha 'main'
    $r = Invoke-Wt $wt1 @('integrate')
    Assert-Wt $r 14 'NICHTS' '8'
    Assert-Bedingung ((Get-Sha 'main') -eq $mainAlt -and (Get-Zaehler) -eq $zaehler) '8' 'main oder Gate-Zähler hat sich verändert' $r

    Write-Output 'Fall 9: main bewegt sich während des Gates nur gate-irrelevant – kein zweiter Gate-Lauf'
    Set-Datei (Join-Path $wt1 'src\neu2.txt') "neu 2`n"
    New-GitCommit $wt1 'IS-001: Einheit 2' @('src/neu2.txt') | Out-Null
    Remove-Item -LiteralPath $marke -ErrorAction SilentlyContinue
    $zaehler = Get-Zaehler
    $env:WT_SMOKE_BEWEGEN = 'irrelevant'
    try {
        $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-001')
    } finally {
        $env:WT_SMOKE_BEWEGEN = $null
    }
    Assert-Wt $r 0 'OK' '9'
    Assert-Bedingung ((Test-Path -LiteralPath $marke) -and (Test-Objekt 'main:docs/notizen/x.md')) '9' `
        'Das Gate hat main nicht bewegt; der Fall prüft so nichts' $r
    Assert-Bedingung ((Get-Zaehler) -eq $zaehler + 1) '9' "Gate lief $((Get-Zaehler) - $zaehler)-mal statt einmal" $r
    Assert-Bedingung ((Get-Sha 'main') -eq (Get-Sha 'is-001-demo') -and (Test-Objekt 'main:src/neu2.txt')) '9' `
        'main steht nicht auf dem rebasten Branch-Tip' $r
    $nachweis = Get-Nachweis (Get-Sha 'main^{tree}') '9'
    Assert-Bedingung ($nachweis -and $nachweis.abgeleitetVon) '9' 'Abgeleiteter Gate-Nachweis (abgeleitetVon) für den integrierten Tree fehlt' $r

    Write-Output 'Fall 10: main bewegt sich während des Gates gate-relevant – zweiter Gate-Lauf'
    Set-Datei (Join-Path $wt1 'src\neu3.txt') "neu 3`n"
    New-GitCommit $wt1 'IS-001: Einheit 3' @('src/neu3.txt') | Out-Null
    Remove-Item -LiteralPath $marke -ErrorAction SilentlyContinue
    $zaehler = Get-Zaehler
    $env:WT_SMOKE_BEWEGEN = 'relevant'
    try {
        $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-001')
    } finally {
        $env:WT_SMOKE_BEWEGEN = $null
    }
    Assert-Wt $r 0 'OK' '10'
    Assert-Bedingung ((Test-Path -LiteralPath $marke) -and (Test-Objekt 'main:src/b.txt')) '10' `
        'Das Gate hat main nicht bewegt; der Fall prüft so nichts' $r
    Assert-Bedingung ((Get-Zaehler) -eq $zaehler + 2) '10' "Gate lief $((Get-Zaehler) - $zaehler)-mal statt zweimal" $r
    Assert-Bedingung ((Get-Sha 'main') -eq (Get-Sha 'is-001-demo') -and (Test-Objekt 'main:src/neu3.txt')) '10' `
        'main steht nicht auf dem rebasten Branch-Tip' $r
    $nachweis = Get-Nachweis (Get-Sha 'main^{tree}') '10'
    Assert-Bedingung ($nachweis -and -not $nachweis.abgeleitetVon) '10' 'Für den integrierten Tree fehlt ein echter, nicht abgeleiteter Gate-Nachweis' $r

    Write-Output 'Fall 11: Konflikt – Rebase abgebrochen, ALTE_BASIS/ALTER_TIP gemeldet, nichts verändert'
    $r = Invoke-Wt $haupt @('start', '-Key', 'IS-011', '-Slug', 'konflikt')
    Assert-Wt $r 0 'OK' '11'
    $wt11 = Join-Path $wtWurzel 'is-011'
    Set-Datei (Join-Path $wt11 'src\a.txt') "zeile 1 zweig`nzeile 2`nzeile 3`nzeile 4`nzeile 5`n"
    New-GitCommit $wt11 'IS-011: a.txt im Branch' @('src/a.txt') | Out-Null
    Set-Datei (Join-Path $haupt 'src\a.txt') "zeile 1 main`nzeile 2`nzeile 3`nzeile 4`nzeile 5`n"
    New-GitCommit $haupt 'main: a.txt' @('src/a.txt') | Out-Null
    $basis = Get-GitWert $haupt @('merge-base', 'main', 'is-011-konflikt')
    $tip11 = Get-Sha 'is-011-konflikt'
    $mainAlt = Get-Sha 'main'
    $zaehler = Get-Zaehler
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-011')
    Assert-Wt $r 10 'KONFLIKT' '11'
    Assert-Bedingung ($r.Text -cmatch 'ALTE_BASIS=([0-9a-f]{7,40})' -and $basis.StartsWith($Matches[1])) '11' "ALTE_BASIS=$basis fehlt in der Ausgabe" $r
    Assert-Bedingung ($r.Text -cmatch 'ALTER_TIP=([0-9a-f]{7,40})' -and $tip11.StartsWith($Matches[1])) '11' "ALTER_TIP=$tip11 fehlt in der Ausgabe" $r
    Assert-Bedingung ($r.Text -match 'src[\\/]a\.txt') '11' 'Die Konfliktdatei src/a.txt wird nicht genannt' $r
    Assert-Bedingung ((Get-Sha 'is-011-konflikt') -eq $tip11 -and (Get-Sha 'main') -eq $mainAlt) '11' 'Branch-Tip oder main hat sich verändert' $r
    Assert-Bedingung (-not (Test-OffenerVorgang $wt11) -and (Get-Zweig $wt11) -ceq 'is-011-konflikt' -and
        @(Get-Aenderungen $wt11).Count -eq 0) '11' 'Worktree hat einen offenen Rebase oder ist nicht sauber' $r
    Assert-Bedingung ((Get-Zaehler) -eq $zaehler) '11' 'Gate lief trotz Konflikt' $r

    Write-Output 'Fall 12: rotes Gate meldet ROT, main bleibt unverändert'
    $r = Invoke-Wt $haupt @('start', '-Key', 'IS-012', '-Slug', 'rot')
    Assert-Wt $r 0 'OK' '12'
    $wt12 = Join-Path $wtWurzel 'is-012'
    Set-Datei (Join-Path $wt12 'ROT') "rot`n"
    New-GitCommit $wt12 'IS-012: macht das Gate rot' @('ROT') | Out-Null
    $mainAlt = Get-Sha 'main'
    $zaehler = Get-Zaehler
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-012')
    Assert-Wt $r 11 'ROT' '12'
    Assert-Bedingung ((Get-Sha 'main') -eq $mainAlt) '12' 'main hat sich trotz rotem Gate verändert' $r
    Assert-Bedingung ((Get-Zaehler) -eq $zaehler + 1) '12' 'Gate lief nicht genau einmal' $r
    Assert-Bedingung ($r.Text.Contains('GATE-ROT')) '12' 'Die letzten Zeilen des Gate-Logs fehlen in der Ausgabe' $r
    Assert-Bedingung (-not $r.Text.Contains('Branch wurde rebased')) '12' 'Meldet einen Rebase, obwohl der Branch main schon enthielt' $r

    Write-Output 'Fall 13: projektplan.md (nurAufMain) und .ai-sdlc/arbeitsbaeume.json (immer nurAufMain) im Branch – commit und integrate blockiert'
    $r = Invoke-Wt $haupt @('start', '-Key', 'IS-013', '-Slug', 'plan')
    Assert-Wt $r 0 'OK' '13'
    $wt13 = Join-Path $wtWurzel 'is-013'
    [IO.File]::AppendAllText((Join-Path $wt13 'projektplan.md'), "- Eintrag aus dem Branch`n")
    $kopf = Get-Sha 'HEAD' $wt13
    $r = Invoke-Wt $wt13 @('commit', '-Nachricht', 'IS-013: Projektplan', 'projektplan.md')
    Assert-Wt $r 12 'BLOCKIERT' '13'
    Assert-Bedingung ((Get-Sha 'HEAD' $wt13) -eq $kopf) '13' 'commit hat projektplan.md im Worktree trotzdem committet' $r
    Assert-Bedingung (Test-Menge @(Get-Aenderungen $wt13) @(' M projektplan.md')) '13' 'Die Änderung an projektplan.md ging verloren' $r
    New-GitCommit $wt13 'IS-013: Projektplan am Werkzeug vorbei' @('projektplan.md') | Out-Null
    $mainAlt = Get-Sha 'main'
    $zaehler = Get-Zaehler
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-013')
    Assert-Wt $r 12 'BLOCKIERT' '13'
    Assert-Bedingung ((Get-Sha 'main') -eq $mainAlt) '13' 'main hat sich verändert' $r
    Assert-Bedingung ((Get-Zaehler) -eq $zaehler) '13' 'Gate lief, obwohl die nurAufMain-Prüfung vorher blockieren muss' $r
    # Die Konfigurationsdatei gehört immer zu nurAufMain, auch ohne Eintrag (konfigBasis nennt nur projektplan.md).
    $konfig13 = Join-Path $wt13 '.ai-sdlc\arbeitsbaeume.json'
    $konfig13Neu = New-KonfigText @{ gateIrrelevant = @('docs/notizen/', 'docs/') }
    Set-Datei $konfig13 $konfig13Neu
    $kopf = Get-Sha 'HEAD' $wt13
    $r = Invoke-Wt $wt13 @('commit', '-Nachricht', 'IS-013: Konfiguration', '.ai-sdlc/arbeitsbaeume.json')
    Assert-Wt $r 12 'BLOCKIERT' '13'
    Assert-Bedingung ((Get-Sha 'HEAD' $wt13) -eq $kopf) '13' 'commit hat .ai-sdlc/arbeitsbaeume.json im Worktree trotzdem committet' $r
    Assert-Bedingung (Test-Menge @(Get-Aenderungen $wt13) @(' M .ai-sdlc/arbeitsbaeume.json')) '13' 'Die Änderung an der Konfiguration ging verloren' $r
    # Branch, der nur die Konfiguration ändert (der projektplan-Commit wird verworfen)
    Get-GitZeilen $wt13 @('reset', '-q', '--hard', 'HEAD~1') | Out-Null
    Set-Datei $konfig13 $konfig13Neu
    New-GitCommit $wt13 'IS-013: Konfiguration am Werkzeug vorbei' @('.ai-sdlc/arbeitsbaeume.json') | Out-Null
    $mainAlt = Get-Sha 'main'
    $zaehler = Get-Zaehler
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-013')
    Assert-Wt $r 12 'BLOCKIERT' '13'
    Assert-Bedingung ($r.WtZeile -match 'arbeitsbaeume\.json') '13' 'Die Meldung nennt die im Branch geänderte Konfigurationsdatei nicht' $r
    Assert-Bedingung ((Get-Sha 'main') -eq $mainAlt -and (Get-Zaehler) -eq $zaehler) '13' `
        'Trotz geänderter Konfiguration im Branch wurden main oder Gate angefasst' $r

    Write-Output 'Fall 14: doppelte ADR-Nummer nach dem Rebase wird blockiert'
    $r = Invoke-Wt $haupt @('start', '-Key', 'IS-014', '-Slug', 'adr')
    Assert-Wt $r 0 'OK' '14'
    $wt14 = Join-Path $wtWurzel 'is-014'
    Set-Datei (Join-Path $wt14 'docs\adr\ADR-0002-zweig.md') "# ADR-0002 aus dem Branch`n"
    New-GitCommit $wt14 'IS-014: ADR-0002' @('docs/adr/ADR-0002-zweig.md') | Out-Null
    Set-Datei (Join-Path $haupt 'docs\adr\ADR-0002-main.md') "# ADR-0002 auf main`n"
    New-GitCommit $haupt 'ADR-0002: registriert' @('docs/adr/ADR-0002-main.md') | Out-Null
    $mainAlt = Get-Sha 'main'
    $zaehler = Get-Zaehler
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-014')
    Assert-Wt $r 12 'BLOCKIERT' '14'
    Assert-Bedingung ((Get-Sha 'main') -eq $mainAlt) '14' 'main hat sich verändert' $r
    Assert-Bedingung ((Get-Zaehler) -eq $zaehler) '14' 'Gate lief, obwohl die Nummernprüfung vorher blockieren muss' $r

    Write-Output 'Fall 15: uncommittete Änderung im Hauptcheckout blockiert den ff (would be overwritten)'
    $r = Invoke-Wt $haupt @('start', '-Key', 'IS-015', '-Slug', 'cdatei')
    Assert-Wt $r 0 'OK' '15'
    $wt15 = Join-Path $wtWurzel 'is-015'
    Set-Datei (Join-Path $wt15 'src\c.txt') "c 1 zweig`nc 2`nc 3`n"
    New-GitCommit $wt15 'IS-015: c.txt' @('src/c.txt') | Out-Null
    $cHaupt = Join-Path $haupt 'src\c.txt'
    $cAlt = Read-Text $cHaupt
    $cLokal = "c lokal und uncommittet`n"
    [IO.File]::WriteAllText($cHaupt, $cLokal)
    $mainAlt = Get-Sha 'main'
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-015')
    Assert-Wt $r 12 'BLOCKIERT' '15'
    Assert-Bedingung ((Get-Sha 'main') -eq $mainAlt) '15' 'main hat sich verändert' $r
    Assert-Bedingung ((Read-Text $cHaupt) -ceq $cLokal) '15' 'Die uncommittete Datei im Hauptcheckout wurde verändert' $r
    Assert-Bedingung ($r.Text -match 'src[\\/]c\.txt') '15' 'Die betroffene Datei src/c.txt wird nicht genannt' $r
    [IO.File]::WriteAllText($cHaupt, $cAlt)
    Assert-Bedingung (@(Get-Aenderungen $haupt).Count -eq 0) '15' 'Hauptcheckout ließ sich nicht zurücksetzen'

    # In den Fällen 16 und 17 hat main einen neuen Commit: Ein Rebase vor den Vorbedingungen würde den
    # Branch-Tip verschieben und fiele so auf, auch wenn eine spätere Prüfung noch blockiert.
    Write-Output 'Fall 16: unsauberer Worktree blockiert integrate vor dem Rebase'
    Set-Datei (Join-Path $haupt 'src\d.txt') "d 1`n"
    New-GitCommit $haupt 'main: d.txt' @('src/d.txt') | Out-Null
    $entwurf = Join-Path $wt15 'entwurf.txt'
    Set-Datei $entwurf "ungetrackt`n"
    $mainAlt = Get-Sha 'main'
    $tip15 = Get-Sha 'is-015-cdatei'
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-015')
    Assert-Wt $r 12 'BLOCKIERT' '16'
    Assert-Bedingung ((Get-Sha 'main') -eq $mainAlt -and (Get-Sha 'is-015-cdatei') -eq $tip15) '16' 'main oder Branch hat sich verändert' $r
    Assert-Bedingung (Test-Path -LiteralPath $entwurf) '16' 'Die ungetrackte Datei im Worktree wurde gelöscht' $r
    Remove-Item -LiteralPath $entwurf

    Write-Output 'Fall 17: Hauptcheckout nicht auf main blockiert integrate vor dem Rebase'
    Get-GitZeilen $haupt @('switch', '-q', '-c', 'nebenzweig') | Out-Null
    $mainAlt = Get-Sha 'main'
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-015')
    Assert-Wt $r 12 'BLOCKIERT' '17'
    Assert-Bedingung ((Get-Zweig $haupt) -ceq 'nebenzweig') '17' 'wt hat im Hauptcheckout den Branch gewechselt' $r
    Assert-Bedingung ((Get-Sha 'main') -eq $mainAlt -and (Get-Sha 'nebenzweig') -eq $mainAlt) '17' 'main oder nebenzweig wurde bewegt' $r
    Assert-Bedingung ((Get-Sha 'is-015-cdatei') -eq $tip15) '17' 'Der Branch wurde trotz Blockade rebast' $r
    Get-GitZeilen $haupt @('switch', '-q', 'main') | Out-Null
    Get-GitZeilen $haupt @('branch', '-q', '-d', 'nebenzweig') | Out-Null

    # Fall 19 läuft vor Fall 18, weil finish den Worktree is-001 entfernt.
    Write-Output 'Fall 19: status nennt die Worktrees mit vollem Pfad, markiert offenen Rebase und integrierte Branches und zeigt Reste unter worktreeRoot'
    $rebase = Invoke-Git -Ort $wt11 -A @('rebase', 'main') -DarfScheitern
    if ($rebase.Code -eq 0 -or -not (Test-OffenerVorgang $wt11)) {
        throw 'Fall 19: Vorbereitung gescheitert – in is-011 entstand kein offener Rebase'
    }
    # Nicht registrierte Ordner unter worktreeRoot: ein Gate-Rest (räumt Fall 20 ab) und ein Issue-Rest.
    $restGate = Join-Path $wtWurzel '_gate-4242'
    $restIssue = Join-Path $wtWurzel 'is-099'
    Set-Datei (Join-Path $restGate 'rest.txt') "rest`n"
    Set-Datei (Join-Path $restIssue 'rest.txt') "rest`n"
    # Zum nicht leeren Rest is-099 gehört ein integrierter Branch: Abschluss nicht per wt finish, sondern Mensch.
    Get-GitZeilen $haupt @('branch', 'is-099-rest', 'main') | Out-Null
    $r = Invoke-Wt $haupt @('status')
    Get-GitZeilen $haupt @('branch', '-q', '-D', 'is-099-rest') | Out-Null
    Assert-Wt $r 0 'OK' '19'
    Assert-Bedingung ($r.Text.Contains('is-001')) '19' 'status nennt is-001 nicht' $r
    Assert-Bedingung (Test-PfadInText $r.Text $wt1) '19' "status nennt den vollen Pfad von is-001 nicht ($wt1)" $r
    Assert-Bedingung (@($r.Text -split "`n" | Where-Object { $_.Contains('is-011') -and $_.Contains('REBASE') }).Count -ge 1) '19' `
        'status markiert den offenen Rebase in is-011 nicht mit REBASE' $r
    Assert-Bedingung (Test-Zeile $r @([regex]::Escape('Rest (nicht registriert)'), '_gate-4242')) '19' `
        "status zeigt den nicht registrierten Ordner _gate-4242 nicht als 'Rest (nicht registriert)'" $r
    Assert-Bedingung (Test-Zeile $r @([regex]::Escape('Rest (nicht registriert)'), 'is-099')) '19' `
        "status zeigt den nicht registrierten Ordner is-099 nicht als 'Rest (nicht registriert)'" $r
    Assert-Bedingung ((Test-Zeile $r @('is-099', 'Rest\b.*\bentfernen')) -and -not (Test-Zeile $r @('is-099', 'wt finish'))) '19' `
        "status rät beim nicht leeren Rest is-099 (Branch integriert) zu 'wt finish' statt zu 'Rest entfernen, Mensch'" $r
    $zeile001 = @($r.Text -split "`n" | Where-Object { $_ -match '^\s*is-001\s*\|' })
    $zeile015 = @($r.Text -split "`n" | Where-Object { $_ -match '^\s*is-015\s*\|' })
    Assert-Bedingung ($zeile001.Count -eq 1 -and $zeile001[0] -match '\bintegriert\b') '19' `
        "status markiert die Zeile von is-001 (Branch vollständig in main) nicht mit 'integriert'" $r
    Assert-Bedingung ($zeile015.Count -eq 1 -and $zeile015[0] -notmatch '(?<!nicht )\bintegriert\b') '19' `
        "status markiert die Zeile von is-015 (Commit nicht in main) als 'integriert'" $r
    Remove-Item -LiteralPath $restIssue -Recurse -Force
    Get-GitZeilen $wt11 @('rebase', '--abort') | Out-Null
    Assert-Bedingung (-not (Test-OffenerVorgang $wt11) -and @(Get-Aenderungen $wt11).Count -eq 0) '19' 'Rebase in is-011 ließ sich nicht abbrechen'

    Write-Output 'Fall 18: finish verweigert vor der Integration und räumt danach auf'
    $r = Invoke-Wt $haupt @('finish', '-Key', 'IS-015')
    Assert-Wt $r 12 'BLOCKIERT' '18'
    Assert-Bedingung ((Test-Path -LiteralPath $wt15) -and (Test-Zweig 'is-015-cdatei')) '18' `
        'finish hat einen nicht integrierten Worktree oder Branch entfernt' $r
    $logQuelle = Join-Path $wt1 '.gate-logs'
    $logs = @(Get-ChildItem -LiteralPath $logQuelle -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{
                Rel  = [IO.Path]::GetRelativePath($logQuelle, $_.FullName)
                Hash = (Get-FileHash -LiteralPath $_.FullName).Hash
            }
        })
    if ($logs.Count -eq 0) {
        throw 'Fall 18: Vorbereitung gescheitert – im Worktree is-001 liegen keine Gate-Logs'
    }
    $r = Invoke-Wt $haupt @('finish', '-Key', 'IS-001')
    Assert-Wt $r 0 'OK' '18'
    Assert-Bedingung (-not (Test-Path -LiteralPath $wt1)) '18' 'Der Worktree-Ordner is-001 existiert noch' $r
    Assert-Bedingung (-not (Test-Zweig 'is-001-demo')) '18' 'Branch is-001-demo wurde nicht gelöscht' $r
    Assert-Bedingung (@(Get-WorktreeEintraege | Where-Object { $_ -match '[\\/]is-001$' }).Count -eq 0) '18' 'Worktree is-001 ist noch registriert' $r
    $ablage = Join-Path $haupt '.gate-logs\_worktrees\is-001'
    foreach ($log in $logs) {
        $ziel = Join-Path $ablage $log.Rel
        Assert-Bedingung ((Test-Path -LiteralPath $ziel) -and (Get-FileHash -LiteralPath $ziel).Hash -eq $log.Hash) '18' `
            "Gate-Log fehlt oder weicht ab: .gate-logs/_worktrees/is-001/$($log.Rel)" $r
    }
    Assert-Bedingung (@(Get-ChildItem -LiteralPath $ablage -Filter 'wt-gate-*.log' -File).Count -ge 1) '18' 'Keine wt-gate-*.log in der Ablage' $r
    Assert-Bedingung ((Get-Zweig $haupt) -ceq 'main' -and @(Get-Aenderungen $haupt).Count -eq 0) '18' 'Hauptcheckout steht nach finish nicht sauber auf main' $r

    Write-Output 'Fall 20: commit -Gate prüft HEAD plus genannte Dateien in einem temporären Worktree (mit allen Pflichtdateien)'
    $rotHaupt = Join-Path $haupt 'ROT'
    Set-Datei $rotHaupt "fremde Datei einer anderen Session`n"
    [IO.File]::WriteAllText($cHaupt, "c 1`nc 2 fix`nc 3`n")
    $kopf = Get-Sha 'HEAD'
    $zaehler = Get-Zaehler
    $r = Invoke-Wt $haupt @('commit', '-Nachricht', 'Fix: c.txt', '-Gate', 'src/c.txt')
    Assert-Wt $r 0 'OK' '20'
    Assert-Bedingung ((Get-Zaehler) -eq $zaehler + 1) '20' 'Gate lief nicht genau einmal' $r
    Assert-Bedingung ((Get-Sha 'HEAD~1') -eq $kopf -and (Test-Menge @(Get-CommitDateien $haupt) @('src/c.txt'))) '20' `
        'Es entstand nicht genau ein Commit mit src/c.txt' $r
    $rest = @(Get-Aenderungen $haupt)
    Assert-Bedingung (Test-Menge $rest @('?? ROT')) '20' "Unerwarteter Status im Hauptcheckout: $($rest -join ', ')" $r
    Assert-Bedingung (-not (Test-Path -LiteralPath $restGate)) '20' 'Der nicht registrierte Rest _gate-4242 unter worktreeRoot wurde nicht entfernt' $r
    Assert-Bedingung (-not (Test-GateReste)) '20' 'Der temporäre _gate-Worktree wurde nicht entfernt' $r
    [IO.File]::WriteAllText($cHaupt, "c 1`nc 2 fix 2`nc 3`n")
    $kopf = Get-Sha 'HEAD'
    $zaehler = Get-Zaehler
    $r = Invoke-Wt $haupt @('commit', '-Nachricht', 'Fix: rot', '-Gate', 'src/c.txt', 'ROT')
    Assert-Wt $r 11 'ROT' '20'
    Assert-Bedingung ((Get-Sha 'HEAD') -eq $kopf) '20' 'Trotz rotem Gate entstand ein Commit' $r
    Assert-Bedingung ((Get-Zaehler) -eq $zaehler + 1) '20' 'Gate lief nicht genau einmal' $r
    $rest = @(Get-Aenderungen $haupt)
    Assert-Bedingung (Test-Menge $rest @(' M src/c.txt', '?? ROT')) '20' "Unerwarteter Status im Hauptcheckout: $($rest -join ', ')" $r
    Assert-Bedingung (-not (Test-GateReste)) '20' 'Der temporäre _gate-Worktree wurde nicht entfernt' $r
    Remove-Item -LiteralPath $rotHaupt
    Get-GitZeilen $haupt @('checkout', '-q', '--', 'src/c.txt') | Out-Null

    Write-Output 'Fall 21: sync und start (Wiederverwendung) mit Konflikt brechen ab, lassen den Worktree sauber; start nennt WORKTREE= und BRANCH='
    $tip11 = Get-Sha 'is-011-konflikt'
    $r = Invoke-Wt $wt11 @('sync')
    Assert-Wt $r 10 'KONFLIKT' '21'
    Assert-Bedingung ((Get-Sha 'is-011-konflikt') -eq $tip11) '21' 'Der Branch-Tip hat sich verändert' $r
    Assert-Bedingung (-not (Test-OffenerVorgang $wt11) -and (Get-Zweig $wt11) -ceq 'is-011-konflikt' -and
        @(Get-Aenderungen $wt11).Count -eq 0) '21' 'Worktree hat einen offenen Rebase oder ist nicht sauber' $r
    $r = Invoke-Wt $haupt @('start', '-Key', 'IS-011')
    Assert-Wt $r 10 'KONFLIKT' '21'
    Assert-Bedingung (Test-GleicherPfad (Get-AusgabeWert $r 'WORKTREE') $wt11) '21' `
        "start (Wiederverwendung) mit Konflikt gibt WORKTREE=$wt11 nicht genau einmal aus" $r
    Assert-Bedingung ((Get-AusgabeWert $r 'BRANCH') -ceq 'is-011-konflikt') '21' `
        'start (Wiederverwendung) mit Konflikt gibt BRANCH=is-011-konflikt nicht genau einmal aus' $r
    Assert-Bedingung ((Get-Sha 'is-011-konflikt') -eq $tip11 -and -not (Test-OffenerVorgang $wt11) -and
        @(Get-Aenderungen $wt11).Count -eq 0) '21' 'start hat Branch oder Worktree verändert' $r

    Write-Output 'Fall 22: start hängt einen vorhandenen Branch ohne Worktree wieder an und bringt ihn auf den Stand von main'
    $r = Invoke-Wt $haupt @('start', '-Key', 'IS-022', '-Slug', 'ohne-wt')
    Assert-Wt $r 0 'OK' '22'
    $wt22 = Join-Path $wtWurzel 'is-022'
    Set-Datei (Join-Path $wt22 'src\neu22.txt') "neu 22`n"
    $sha22 = New-GitCommit $wt22 'IS-022: Einheit 1' @('src/neu22.txt')
    Get-GitZeilen $haupt @('worktree', 'remove', $wt22) | Out-Null
    if ((Test-Path -LiteralPath $wt22) -or -not (Test-Zweig 'is-022-ohne-wt')) {
        throw 'Fall 22: Vorbereitung gescheitert – Worktree is-022 nicht entfernt oder Branch verloren'
    }
    Set-Datei (Join-Path $haupt 'src\e.txt') "e 1`n"
    $mainNeu = New-GitCommit $haupt 'main: e.txt' @('src/e.txt')
    $r = Invoke-Wt $haupt @('status')
    Assert-Wt $r 0 'OK' '22'
    Assert-Bedingung ($r.Text.Contains('is-022-ohne-wt')) '22' 'status nennt den Branch ohne Worktree nicht' $r
    $notiz22 = Join-Path $haupt 'issues\IS-022-ohne-wt\notiz.md'
    Set-Datei $notiz22 "uncommittete Notiz`n"
    $r = Invoke-Wt $haupt @('start', '-Key', 'IS-022')
    Assert-Wt $r 12 'BLOCKIERT' '22'
    Assert-Bedingung (-not (Test-Path -LiteralPath $wt22) -and -not (Test-Registriert $wt22)) '22' `
        'start hat den Branch trotz unsauberem Issue-Ordner angehängt' $r
    Assert-Bedingung ((Get-Sha 'is-022-ohne-wt') -eq $sha22) '22' 'Der Branch wurde trotz Blockade verändert' $r
    Remove-Item -LiteralPath (Split-Path -Parent $notiz22) -Recurse -Force
    $r = Invoke-Wt $haupt @('start', '-Key', 'IS-022')
    Assert-Wt $r 0 'OK' '22'
    Assert-Bedingung (Test-Path -LiteralPath (Join-Path $wt22 '.git')) '22' 'Worktree is-022 wurde nicht angelegt' $r
    Assert-Bedingung ((Get-Zweig $wt22) -ceq 'is-022-ohne-wt' -and (Get-Sha 'HEAD' $wt22) -eq (Get-Sha 'is-022-ohne-wt')) '22' `
        'Worktree steht nicht auf dem vorhandenen Branch' $r
    Assert-Bedingung ((Get-Sha 'HEAD~1' $wt22) -eq $mainNeu -and (Test-Vorfahr 'main' 'is-022-ohne-wt')) '22' `
        'Der angehängte Branch wurde nicht auf den aktuellen main gebracht' $r
    Assert-Bedingung ((Get-GitWert $wt22 @('log', '-1', '--format=%s')) -ceq 'IS-022: Einheit 1') '22' 'Der eigene Commit des Branches fehlt' $r
    Assert-Bedingung ((Test-Path -LiteralPath (Join-Path $wt22 'src\neu22.txt')) -and (Test-Path -LiteralPath (Join-Path $wt22 'src\e.txt'))) '22' `
        'Commit-Inhalt oder neuer main-Stand fehlt im Worktree' $r
    Assert-Bedingung (@(Get-GitZeilen $haupt @('branch', '--list', 'is-022*')).Count -eq 1) '22' 'start hat einen zusätzlichen Branch angelegt' $r
    $fehlt = @(Get-PflichtFehler $wt22)
    Assert-Bedingung ($fehlt.Count -eq 0) '22' "Pflichtdateien fehlen oder weichen ab: $($fehlt -join ', ')" $r

    Write-Output 'Fall 23: commit im Hauptcheckout prüft Nummern über HEAD plus genannte Dateien'
    $adrDoppelt = Join-Path $haupt 'docs\adr\ADR-0002-doppelt.md'
    Set-Datei $adrDoppelt "# ADR-0002 doppelt`n"
    $kopf = Get-Sha 'HEAD'
    $r = Invoke-Wt $haupt @('commit', '-Nachricht', 'ADR-0002: doppelt', 'docs/adr/ADR-0002-doppelt.md')
    Assert-Wt $r 12 'BLOCKIERT' '23'
    Assert-Bedingung ((Get-Sha 'HEAD') -eq $kopf) '23' 'Trotz doppelter Nummer entstand ein Commit' $r
    $rest = @(Get-Aenderungen $haupt)
    Assert-Bedingung (Test-Menge $rest @('?? docs/adr/ADR-0002-doppelt.md')) '23' "Index oder Status verändert: $($rest -join ', ')" $r
    Remove-Item -LiteralPath $adrDoppelt

    Write-Output 'Fall 24: commit -Gate – ändert sich eine genannte Datei während des Gates, committet wt die gegateten Bytes und meldet die Abweichung'
    $gegatet24 = "c 1`nc 2 fix 3`nc 3`n"
    [IO.File]::WriteAllText($cHaupt, $gegatet24)
    $kopf = Get-Sha 'HEAD'
    $zaehler = Get-Zaehler
    $env:WT_SMOKE_AENDERN = 'src/c.txt'
    try {
        $r = Invoke-Wt $haupt @('commit', '-Nachricht', 'Fix: Datei waehrend des Gates', '-Gate', 'src/c.txt')
    } finally {
        $env:WT_SMOKE_AENDERN = $null
    }
    Assert-Wt $r 0 'OK' '24'
    Assert-Bedingung ((Get-Sha 'HEAD~1') -eq $kopf -and (Test-Menge @(Get-CommitDateien $haupt) @('src/c.txt'))) '24' `
        'Es entstand nicht genau ein Commit mit src/c.txt' $r
    Assert-Bedingung ((Get-GitBlob $haupt 'HEAD:src/c.txt') -ceq $gegatet24) '24' 'Committet wurde nicht der gegatete Inhalt von src/c.txt' $r
    Assert-Bedingung ((Read-Text $cHaupt) -ceq "waehrend des Gates geaendert`n") '24' 'Die Änderung während des Gates wurde überschrieben' $r
    $hinweis = @($r.Text -split "`n" | Where-Object { $_ -notmatch '^WT: ' })
    Assert-Bedingung (@($hinweis | Where-Object { $_ -match 'src[\\/]c\.txt' }).Count -ge 1 -and
        @($hinweis | Where-Object { $_ -match '(?i)abweich|weicht|ge(ä|ae)ndert|ver(ä|ae)ndert|uncommittet' }).Count -ge 1) '24' `
        'Kein Hinweis, dass die Arbeitskopie von src/c.txt vom gegateten Stand abweicht' $r
    Assert-Bedingung ((Get-Zaehler) -eq $zaehler + 1) '24' 'Gate lief nicht genau einmal' $r
    $rest = @(Get-Aenderungen $haupt)
    Assert-Bedingung (Test-Menge $rest @(' M src/c.txt')) '24' "Index steht nicht auf HEAD oder Status unerwartet: $($rest -join ', ')" $r
    Assert-Bedingung (-not (Test-GateReste)) '24' 'Der temporäre _gate-Worktree wurde nicht entfernt' $r
    Get-GitZeilen $haupt @('checkout', '-q', '--', 'src/c.txt') | Out-Null

    Write-Output 'Fall 25: Merge-Commit im Branch – integrate blockiert, Branch und main bleiben unverändert'
    $r = Invoke-Wt $haupt @('start', '-Key', 'IS-025', '-Slug', 'merge')
    Assert-Wt $r 0 'OK' '25'
    $wt25 = Join-Path $wtWurzel 'is-025'
    Set-Datei (Join-Path $wt25 'src\m.txt') "m`n"
    New-GitCommit $wt25 'IS-025: m.txt' @('src/m.txt') | Out-Null
    Set-Datei (Join-Path $haupt 'src\n.txt') "n`n"
    New-GitCommit $haupt 'main: n.txt' @('src/n.txt') | Out-Null
    Get-GitZeilen $wt25 @('merge', '-q', '--no-ff', '--no-edit', 'main') | Out-Null
    if (@(Get-GitZeilen $haupt @('rev-list', '--merges', 'main..is-025-merge')).Count -ne 1) {
        throw 'Fall 25: Vorbereitung gescheitert – kein Merge-Commit im Branch'
    }
    $tip25 = Get-Sha 'is-025-merge'
    $mainAlt = Get-Sha 'main'
    $zaehler = Get-Zaehler
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-025')
    Assert-Wt $r 12 'BLOCKIERT' '25'
    Assert-Bedingung ($r.WtZeile -match 'Merge-Commit') '25' 'Die Meldung nennt den Merge-Commit nicht' $r
    Assert-Bedingung ((Get-Sha 'main') -eq $mainAlt -and (Get-Sha 'is-025-merge') -eq $tip25) '25' 'main oder Branch hat sich verändert' $r
    Assert-Bedingung ((Get-Zaehler) -eq $zaehler) '25' 'Gate lief trotz Merge-Commit' $r
    Assert-Bedingung (-not (Test-OffenerVorgang $wt25) -and @(Get-Aenderungen $wt25).Count -eq 0) '25' 'Worktree ist nicht sauber' $r

    Write-Output 'Fall 26: merge.autoStash=true – fremde Änderung im Hauptcheckout blockiert den ff, kein Stash'
    $r = Invoke-Wt $haupt @('start', '-Key', 'IS-026', '-Slug', 'autostash')
    Assert-Wt $r 0 'OK' '26'
    $wt26 = Join-Path $wtWurzel 'is-026'
    Set-Datei (Join-Path $wt26 'src\d.txt') "d 1 aus dem Branch`n"
    New-GitCommit $wt26 'IS-026: d.txt' @('src/d.txt') | Out-Null
    $dHaupt = Join-Path $haupt 'src\d.txt'
    $dFremd = "d 1 fremde Arbeit, uncommittet`n"
    [IO.File]::WriteAllText($dHaupt, $dFremd)
    $mainAlt = Get-Sha 'main'
    Get-GitZeilen $haupt @('config', 'merge.autoStash', 'true') | Out-Null
    Get-GitZeilen $haupt @('config', 'rebase.autoStash', 'true') | Out-Null
    try {
        $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-026')
    } finally {
        Invoke-Git -Ort $haupt -A @('config', '--unset', 'merge.autoStash') -DarfScheitern | Out-Null
        Invoke-Git -Ort $haupt -A @('config', '--unset', 'rebase.autoStash') -DarfScheitern | Out-Null
    }
    Assert-Wt $r 12 'BLOCKIERT' '26'
    Assert-Bedingung ((Get-Sha 'main') -eq $mainAlt) '26' 'main hat sich verändert' $r
    Assert-Bedingung ((Read-Text $dHaupt) -ceq $dFremd) '26' 'Die fremde uncommittete Änderung wurde verändert' $r
    Assert-Bedingung (@(Get-GitZeilen $haupt @('stash', 'list')).Count -eq 0) '26' 'Im geteilten Stash liegt ein Eintrag' $r
    $rest = @(Get-Aenderungen $haupt)
    Assert-Bedingung (Test-Menge $rest @(' M src/d.txt')) '26' "Unerwarteter Status im Hauptcheckout: $($rest -join ', ')" $r
    Assert-Bedingung ($r.Text -match 'src[\\/]d\.txt') '26' 'Die betroffene Datei src/d.txt wird nicht genannt' $r
    Get-GitZeilen $haupt @('checkout', '-q', '--', 'src/d.txt') | Out-Null

    Write-Output 'Fall 27: commit mit per git rm gestagter Löschung und git mv – nur der neue Pfad blockiert, alter und neuer Pfad werden committet'
    Set-Datei (Join-Path $wt26 'src\weg.txt') "weg`n"
    Set-Datei (Join-Path $wt26 'src\alt.txt') "alt`n"
    New-GitCommit $wt26 'IS-026: Vorbereitung rm/mv' @('src/weg.txt', 'src/alt.txt') | Out-Null
    Get-GitZeilen $wt26 @('rm', '-q', '--', 'src/weg.txt') | Out-Null
    Get-GitZeilen $wt26 @('mv', 'src/alt.txt', 'src/neu.txt') | Out-Null
    $kopf = Get-Sha 'HEAD' $wt26
    # nur der neue Pfad genannt: committet würde eine Kopie, die gestagte Löschung von src/alt.txt bliebe liegen
    $statusVor = @(Get-Aenderungen $wt26)
    $r = Invoke-Wt $wt26 @('commit', '-Nachricht', 'IS-026: nur neuer Pfad', 'src/neu.txt')
    Assert-Wt $r 12 'BLOCKIERT' '27'
    Assert-Bedingung ($r.Text -match 'src[\\/]alt\.txt') '27' 'Die Meldung nennt den mitzunennenden alten Pfad src/alt.txt nicht' $r
    Assert-Bedingung ((Get-Sha 'HEAD' $wt26) -eq $kopf -and (Test-Menge @(Get-Aenderungen $wt26) $statusVor)) '27' `
        'git mv mit nur neuem Pfad hat committet oder Index bzw. Arbeitsbaum verändert' $r
    $r = Invoke-Wt $wt26 @('commit', '-Nachricht', 'IS-026: weg geloescht, alt umbenannt', 'src/weg.txt', 'src/alt.txt', 'src/neu.txt')
    Assert-Wt $r 0 'OK' '27'
    Assert-Bedingung ((Get-Sha 'HEAD~1' $wt26) -eq $kopf) '27' 'Es entstand nicht genau ein Commit' $r
    $st = @(Get-CommitStatus $wt26)
    Assert-Bedingung (Test-Menge $st @('D src/weg.txt', 'D src/alt.txt', 'A src/neu.txt')) '27' "Commit enthält: $($st -join ', ')" $r
    $rest = @(Get-Aenderungen $wt26)
    Assert-Bedingung ($rest.Count -eq 0) '27' "Worktree nach dem Commit nicht sauber: $($rest -join ', ')" $r
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-026')
    Assert-Wt $r 0 'OK' '27'
    Assert-Bedingung ((Get-Sha 'main') -eq (Get-Sha 'is-026-autostash') -and (Test-Objekt 'main:src/neu.txt') -and
        -not (Test-Objekt 'main:src/alt.txt') -and -not (Test-Objekt 'main:src/weg.txt')) '27' 'main enthält Löschung und Umbenennung nicht' $r
    Assert-Bedingung (@(Get-Aenderungen $haupt).Count -eq 0) '27' 'Hauptcheckout ist nach dem ff nicht sauber' $r

    Write-Output 'Fall 28: finish verweigert bei Prozess im Worktree, laufendem Programm daraus oder Aufruf aus dem Worktree; Junctions fallen ohne ihre Ziele'
    $stand26 = (Get-DateiStand $wt26) -join "`n"
    $r = Invoke-Wt $wt26 @('finish')
    Assert-Wt $r 12 'BLOCKIERT' '28'
    Assert-Bedingung ($r.Text.Contains('-Key') -and $r.Text.Contains('Hauptcheckout')) '28' `
        'Kein Hinweis, finish aus dem Hauptcheckout mit -Key aufzurufen' $r
    Assert-Bedingung ((Test-Registriert $wt26) -and ((Get-DateiStand $wt26) -join "`n") -ceq $stand26 -and (Test-Zweig 'is-026-autostash')) '28' `
        'finish aus dem Worktree hat Worktree, Dateien oder Branch angetastet' $r
    $belegt = Start-Halter -Ort $wt26
    try {
        $r = Invoke-Wt $haupt @('finish', '-Key', 'IS-026')
    } finally {
        Stop-Halter $belegt
    }
    Assert-Wt $r 12 'BLOCKIERT' '28'
    Assert-Bedingung ($r.WtZeile -match 'belegt') '28' 'Die Meldung nennt den belegten Worktree-Ordner nicht' $r
    Assert-Bedingung ((Test-Registriert $wt26) -and ((Get-DateiStand $wt26) -join "`n") -ceq $stand26 -and (Test-Zweig 'is-026-autostash')) '28' `
        'finish hat trotz belegtem Ordner Registrierung, Dateien oder Branch entfernt' $r
    # Ein Programm aus dem Worktree läuft (Arbeitsverzeichnis außerhalb): Umbenennen gelingt, Löschen nicht.
    $pingQuelle = Join-Path ([Environment]::GetFolderPath('System')) 'PING.EXE'
    if (Test-Path -LiteralPath $pingQuelle -PathType Leaf) {
        $pingWt = Join-Path $wt26 '.lokal\bin\ping.exe'
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $pingWt) | Out-Null
        Copy-Item -LiteralPath $pingQuelle -Destination $pingWt
        $stand26 = (Get-DateiStand $wt26) -join "`n"
        $ping = Start-Programm $pingWt @('-n', '120', '127.0.0.1')
        try {
            Start-Sleep -Milliseconds 300
            if ($ping.HasExited) { throw 'Fall 28: Vorbereitung gescheitert – ping.exe aus dem Worktree läuft nicht' }
            $r = Invoke-Wt $haupt @('finish', '-Key', 'IS-026')
        } finally {
            Stop-Programm $ping $pingWt
        }
        Assert-Wt $r 12 'BLOCKIERT' '28'
        Assert-Bedingung ($r.Text -match "(?<!\d)$($ping.Id)(?!\d)" -or $r.Text -match '(?i)[\\/]bin[\\/]ping\.exe') '28' `
            "Die Meldung nennt das laufende Programm (PID $($ping.Id), .lokal/bin/ping.exe) nicht" $r
        Assert-Bedingung ((Test-Registriert $wt26) -and ((Get-DateiStand $wt26) -join "`n") -ceq $stand26 -and (Test-Zweig 'is-026-autostash')) '28' `
            'finish hat trotz laufendem Programm aus dem Worktree Registrierung, Dateien oder Branch entfernt' $r
    } else {
        Write-Output '  Hinweis: PING.EXE fehlt – Teilfall „laufendes Programm aus dem Worktree“ übersprungen.'
    }
    # Junctions im Worktree (npm-file:-Abhängigkeit, geteilter Ordner) zeigen auf Kanarienordner außerhalb;
    # git worktree remove folgt Junctions, finish muss vorher nur die Links entfernen.
    $kanNpm = New-Kanarie 'kanarie-npm'
    $kanCache = New-Kanarie 'kanarie-cache'
    New-Junction (Join-Path $wt26 '.lokal\node_modules\lib-extern') $kanNpm.Pfad
    New-Junction (Join-Path $wt26 '.lokal\cache-link') $kanCache.Pfad
    if (@(Get-Aenderungen $wt26).Count -ne 0) {
        throw 'Fall 28: Vorbereitung gescheitert – die Junctions unter .lokal/ sind nicht ignoriert'
    }
    $r = Invoke-Wt $haupt @('finish', '-Key', 'IS-026')
    Assert-Wt $r 0 'OK' '28'
    Assert-Bedingung ((Test-Kanarie $kanNpm) -and (Test-Kanarie $kanCache)) '28' `
        'finish ist einer Junction gefolgt und hat Dateien außerhalb des Worktrees gelöscht' $r
    Assert-Bedingung ((Test-Zeile $r @('lib-extern', 'kanarie-npm')) -and (Test-Zeile $r @('cache-link', 'kanarie-cache'))) '28' `
        'Die Ausgabe nennt die entfernten Links nicht mit ihrem Ziel' $r
    Assert-Bedingung (-not (Test-Path -LiteralPath $wt26) -and -not (Test-Registriert $wt26) -and -not (Test-Zweig 'is-026-autostash')) '28' `
        'Worktree oder Branch is-026 nach finish noch vorhanden' $r
    Assert-Bedingung ((Get-Zweig $haupt) -ceq 'main' -and @(Get-Aenderungen $haupt).Count -eq 0) '28' 'Hauptcheckout steht nach finish nicht sauber auf main' $r

    Write-Output 'Fall 29: Projektwerte aus HEAD – Prüfung beim Laden, nicht versionierte und uncommittete Konfiguration'
    $r = Invoke-Wt $haupt @('start', '-Key', 'IS-029', '-Slug', 'konfig')
    Assert-Wt $r 0 'OK' '29'
    $wt29 = Join-Path $wtWurzel 'is-029'
    # Der Branch hat hier noch keine eigenen Commits: Ohne Prüfung endete integrate harmlos mit 14.
    Set-KonfigCommit (New-KonfigText @{ nummernPruefung = @([ordered]@{ ordner = 'docs/adr'; muster = '^ADR-\d{4}-' }) }) 'Konfig: Muster ohne Fanggruppe'
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-029')
    Assert-Wt $r 1 'FEHLER' '29'
    Assert-Bedingung ($r.WtZeile -notmatch 'unerwartet') '29' 'Muster ohne Fanggruppe endet in einem unerwarteten Fehler statt in einer Konfigurationsmeldung' $r
    Set-KonfigCommit (New-KonfigText @{ nurAufMain = @('projektplan.md', 'plaene/*.md') }) 'Konfig: Platzhalter in nurAufMain'
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-029')
    Assert-Wt $r 1 'FEHLER' '29'
    Assert-Bedingung ($r.WtZeile -notmatch 'unerwartet') '29' 'Platzhalter in nurAufMain endet in einem unerwarteten Fehler statt in einer Konfigurationsmeldung' $r
    Set-Datei $konfigPfad $konfigText
    Get-GitZeilen $haupt @('rm', '-q', '--cached', '--', '.ai-sdlc/arbeitsbaeume.json') | Out-Null
    Get-GitZeilen $haupt @('commit', '-q', '-m', 'Konfig: nicht mehr versioniert') | Out-Null
    $r = Invoke-Wt $haupt @('status')
    Assert-Wt $r 0 'OK' '29'
    Assert-Bedingung ($r.Text -match 'nicht versioniert') '29' 'Keine WARNUNG zur nicht versionierten Konfiguration' $r
    Get-GitZeilen $haupt @('add', '--', '.ai-sdlc/arbeitsbaeume.json') | Out-Null
    Get-GitZeilen $haupt @('commit', '-q', '-m', 'Konfig: wieder versioniert', '--', '.ai-sdlc/arbeitsbaeume.json') | Out-Null
    Set-Datei (Join-Path $wt29 'src\konfig.txt') "konfig`n"
    New-GitCommit $wt29 'IS-029: konfig.txt' @('src/konfig.txt') | Out-Null
    Set-Datei $konfigPfad (New-KonfigText @{ gateIrrelevant = @('docs/notizen/', 'src/') })
    $mainAlt = Get-Sha 'main'
    $tip29 = Get-Sha 'is-029-konfig'
    $zaehler = Get-Zaehler
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-029')
    Assert-Wt $r 12 'BLOCKIERT' '29'
    Assert-Bedingung ($r.WtZeile -match 'Konfiguration') '29' 'Die Meldung nennt die uncommittet geänderte Konfiguration nicht' $r
    Assert-Bedingung ((Get-Sha 'main') -eq $mainAlt -and (Get-Sha 'is-029-konfig') -eq $tip29 -and (Get-Zaehler) -eq $zaehler) '29' `
        'Trotz uncommitteter Konfiguration wurden main, Branch oder Gate angefasst' $r
    Get-GitZeilen $haupt @('checkout', '-q', '--', '.ai-sdlc/arbeitsbaeume.json') | Out-Null
    Assert-Bedingung (@(Get-Aenderungen $haupt).Count -eq 0) '29' 'Hauptcheckout ließ sich nicht zurücksetzen'

    Write-Output 'Fall 30: Gate-Kette mit scheiterndem ersten Schritt ist rot; ein Rebase im selben Lauf wird gemeldet'
    Set-KonfigCommit (New-KonfigText @{ gate = 'pwsh -NoProfile -Command "exit 3"; pwsh -NoProfile -Command "exit 0"' }) 'Konfig: Gate-Kette'
    $basis = Get-GitWert $haupt @('merge-base', 'main', 'is-029-konfig')
    $tip29 = Get-Sha 'is-029-konfig'
    $mainAlt = Get-Sha 'main'
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-029')
    Assert-Wt $r 11 'ROT' '30'
    Assert-Bedingung ((Get-Sha 'main') -eq $mainAlt) '30' 'main hat sich trotz rotem Gate verändert' $r
    Assert-Bedingung ((Get-Sha 'is-029-konfig~1') -eq $mainAlt) '30' 'Vorbereitung: Der Branch wurde vor dem Gate nicht rebased' $r
    Assert-Bedingung ($r.Text.Contains('Branch wurde rebased')) '30' "Exit 11 meldet nicht 'Branch wurde rebased'" $r
    Assert-Bedingung ($r.Text -cmatch 'ALTE_BASIS=([0-9a-f]{7,40})' -and $basis.StartsWith($Matches[1])) '30' "ALTE_BASIS=$basis fehlt in der Ausgabe" $r
    Assert-Bedingung ($r.Text -cmatch 'ALTER_TIP=([0-9a-f]{7,40})' -and $tip29.StartsWith($Matches[1])) '30' "ALTER_TIP=$tip29 fehlt in der Ausgabe" $r
    Set-KonfigCommit $konfigText 'Konfig: Gate wieder gate.ps1'
    $zaehler = Get-Zaehler
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-029')
    Assert-Wt $r 0 'OK' '30'
    Assert-Bedingung ((Get-Sha 'main') -eq (Get-Sha 'is-029-konfig') -and (Get-Zaehler) -eq $zaehler + 1) '30' `
        'Nach dem Zurücksetzen der Gate-Kette wurde nicht mit genau einem Gate-Lauf integriert' $r

    Write-Output 'Fall 31: leerer, nicht registrierter Rest-Ordner eines integrierten Branches – status zeigt beides, finish räumt ab'
    Get-GitZeilen $haupt @('worktree', 'remove', $wt29) | Out-Null
    New-Item -ItemType Directory -Path $wt29 | Out-Null
    $r = Invoke-Wt $haupt @('status')
    Assert-Wt $r 0 'OK' '31'
    Assert-Bedingung (Test-Zeile $r @([regex]::Escape('Rest (nicht registriert)'), 'is-029(?!-)')) '31' `
        "status zeigt den leeren Ordner is-029 nicht als 'Rest (nicht registriert)'" $r
    Assert-Bedingung (Test-Zeile $r @('is-029-konfig', [regex]::Escape('integriert, ohne Worktree'))) '31' `
        "status zeigt is-029-konfig nicht als 'integriert, ohne Worktree'" $r
    $r = Invoke-Wt $haupt @('finish', '-Key', 'IS-029')
    Assert-Wt $r 0 'OK' '31'
    Assert-Bedingung (-not (Test-Path -LiteralPath $wt29) -and -not (Test-Zweig 'is-029-konfig')) '31' 'Rest-Ordner oder Branch is-029-konfig noch vorhanden' $r

    Write-Output 'Fall 32: nicht ignorierte Gate-Ablage (gateAblage) legt schon start an und trägt sie in info/exclude ein, ohne .gitignore; sie blockiert nichts'
    Set-KonfigCommit (New-KonfigText @{ gateAblage = '.pruef-ablage' }) 'Konfig: gateAblage .pruef-ablage'
    if (Test-Git $haupt @('check-ignore', '-q', '.pruef-ablage/')) {
        throw 'Fall 32: Vorbereitung gescheitert – .pruef-ablage/ ist schon ignoriert'
    }
    $r = Invoke-Wt $haupt @('start', '-Key', 'IS-032', '-Slug', 'ablage')
    Assert-Wt $r 0 'OK' '32'
    $wt32 = Join-Path $wtWurzel 'is-032'
    $exclude = Get-GitWert $haupt @('rev-parse', '--path-format=absolute', '--git-path', 'info/exclude')
    Assert-Bedingung ((Test-Path -LiteralPath (Join-Path $wt32 '.pruef-ablage') -PathType Container) -and
        (Test-Git $wt32 @('check-ignore', '-q', '.pruef-ablage/'))) '32' 'start hat die Gate-Ablage im Worktree nicht angelegt bzw. nicht ignoriert' $r
    Assert-Bedingung ((Test-Path -LiteralPath $exclude) -and
        @(Get-Content -LiteralPath $exclude | Where-Object { $_.Trim() -ceq '/.pruef-ablage/' }).Count -ge 1) '32' `
        "start hat '/.pruef-ablage/' nicht in info/exclude eingetragen" $r
    # Eine Review-Session legt ihre Sicherung vor dem ersten Gate an.
    $sitzung = Join-Path $wt32 '.pruef-ablage\IS-032\r1\manifest-vor.txt'
    Set-Datei $sitzung "manifest`n"
    Set-Datei (Join-Path $wt32 'src\ablage.txt') "ablage`n"
    New-GitCommit $wt32 'IS-032: ablage.txt' @('src/ablage.txt') | Out-Null
    $r = Invoke-Wt $haupt @('sync', '-Key', 'IS-032')
    Assert-Wt $r 0 'OK' '32'
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-032')
    Assert-Wt $r 0 'OK' '32'
    Assert-Bedingung ((Get-Sha 'main') -eq (Get-Sha 'is-032-ablage')) '32' 'main steht nicht auf dem Branch-Tip' $r
    Assert-Bedingung (@(Get-ChildItem -LiteralPath (Join-Path $wt32 '.pruef-ablage') -Filter 'wt-gate-*.log' -File -ErrorAction SilentlyContinue).Count -ge 1) '32' `
        'Gate-Log fehlt unter der konfigurierten Ablage .pruef-ablage im Worktree' $r
    $exclude = Get-GitWert $haupt @('rev-parse', '--path-format=absolute', '--git-path', 'info/exclude')
    Assert-Bedingung ((Test-Path -LiteralPath $exclude) -and @(Get-Content -LiteralPath $exclude | Where-Object { $_.Trim() -ceq '/.pruef-ablage/' }).Count -ge 1) '32' `
        "info/exclude enthält keinen Eintrag '/.pruef-ablage/'" $r
    Assert-Bedingung (Test-Git $haupt @('check-ignore', '-q', '.pruef-ablage/')) '32' '.pruef-ablage/ ist im Hauptcheckout danach nicht ignoriert' $r
    Assert-Bedingung (-not (Test-Path -LiteralPath (Join-Path $wt32 '.pruef-ablage\.gitignore'))) '32' 'wt hat eine .gitignore in der Ablage angelegt' $r
    $r = Invoke-Wt $haupt @('finish', '-Key', 'IS-032')
    Assert-Wt $r 0 'OK' '32'
    $ablage32 = Join-Path $haupt '.pruef-ablage\_worktrees\is-032'
    $sitzungKopie = Join-Path $ablage32 'IS-032\r1\manifest-vor.txt'
    Assert-Bedingung ((Test-Path -LiteralPath $sitzungKopie) -and (Read-Text $sitzungKopie) -ceq "manifest`n") '32' `
        'Die Sitzungsablage wurde nicht nach .pruef-ablage/_worktrees/is-032 gesichert' $r
    Assert-Bedingung (@(Get-ChildItem -LiteralPath $ablage32 -Filter 'wt-gate-*.log' -File -ErrorAction SilentlyContinue).Count -ge 1) '32' `
        'Keine wt-gate-*.log in der gesicherten Ablage' $r
    Assert-Bedingung (-not (Test-Path -LiteralPath (Join-Path $haupt '.pruef-ablage\.gitignore'))) '32' 'wt hat im Hauptcheckout eine .gitignore in der Ablage angelegt' $r
    Assert-Bedingung (-not (Test-Path -LiteralPath $wt32) -and -not (Test-Zweig 'is-032-ablage')) '32' 'Worktree oder Branch is-032 nach finish noch vorhanden' $r
    Assert-Bedingung ((Get-Zweig $haupt) -ceq 'main' -and @(Get-Aenderungen $haupt).Count -eq 0) '32' 'Hauptcheckout steht nach finish nicht sauber auf main' $r
    Set-KonfigCommit $konfigText 'Konfig: gateAblage wieder Standard'

    Write-Output 'Fall 33: Änderung im Worktree während des Wartens auf die Integrationssperre blockiert; status prüft Sperren nur lesend'
    $r = Invoke-Wt $haupt @('start', '-Key', 'IS-033', '-Slug', 'warten')
    Assert-Wt $r 0 'OK' '33'
    $wt33 = Join-Path $wtWurzel 'is-033'
    Set-Datei (Join-Path $wt33 'src\w.txt') "w`n"
    New-GitCommit $wt33 'IS-033: w.txt' @('src/w.txt') | Out-Null
    $integrationLock = Join-Path $common 'ai-sdlc\integration.lock'
    $waehrend = Join-Path $wt33 'src\waehrend-warten.txt'
    $mainAlt = Get-Sha 'main'
    $tip33 = Get-Sha 'is-033-warten'
    $zaehler = Get-Zaehler
    $sperre = Start-Halter -Ort $testPath -Datei $integrationLock -Teilen None
    try {
        $r = Invoke-Wt $haupt @('status')
        Assert-Wt $r 0 'OK' '33'
        Assert-Bedingung ($r.Text -match 'Integrationssperre belegt') '33' 'status erkennt die exklusiv gehaltene Integrationssperre nicht' $r
        $hinter = Start-WtHintergrund $haupt @('integrate', '-Key', 'IS-033')
        if (-not (Wait-WtZeile $hinter 'warte.*Integrationssperre' 60)) {
            throw "Fall 33: Vorbereitung gescheitert – integrate wartet nicht auf die Integrationssperre: $($hinter.Zeilen -join ' | ')"
        }
        Set-Datei $waehrend "neu während des Wartens`n"
    } finally {
        Stop-Halter $sperre
    }
    $r = Complete-WtHintergrund $hinter 120
    Assert-Wt $r 12 'BLOCKIERT' '33'
    Assert-Bedingung ($r.WtZeile -match 'Wartezeit') '33' 'Die Meldung nennt die Veränderung während der Wartezeit nicht' $r
    Assert-Bedingung ((Get-Sha 'main') -eq $mainAlt -and (Get-Sha 'is-033-warten') -eq $tip33 -and (Get-Zaehler) -eq $zaehler) '33' `
        'Trotz Veränderung während der Wartezeit wurden main, Branch oder Gate angefasst' $r
    Assert-Bedingung (Test-Path -LiteralPath $waehrend) '33' 'Die während der Wartezeit angelegte Datei wurde gelöscht' $r
    Remove-Item -LiteralPath $waehrend
    $sperrDateien = @(Get-ChildItem -LiteralPath (Join-Path $common 'ai-sdlc') -Filter '*.lock' -File)
    try {
        foreach ($d in $sperrDateien) { $d.IsReadOnly = $true }
        $r = Invoke-Wt $haupt @('status')
    } finally {
        foreach ($d in $sperrDateien) { $d.IsReadOnly = $false }
    }
    Assert-Wt $r 0 'OK' '33'

    Write-Output 'Fall 34: Gate startet einen erbenden Hintergrundprozess – integrate wartet nur auf das Gate selbst'
    $daemonMarke = Join-Path $testPath 'daemon.pid'
    $uhr = [Diagnostics.Stopwatch]::StartNew()
    $env:WT_SMOKE_DAEMON = $daemonMarke
    try {
        $hinter = Start-WtHintergrund $haupt @('integrate', '-Key', 'IS-033')
    } finally {
        $env:WT_SMOKE_DAEMON = $null
    }
    $daemon = $null
    try {
        $beendet = $hinter.P.WaitForExit(25000)
        $dauer = [math]::Round($uhr.Elapsed.TotalSeconds, 1)
        if (Test-Path -LiteralPath $daemonMarke) { $daemon = Add-ProzessAusDatei $daemonMarke }
    } finally {
        if ($null -ne $daemon -and -not $daemon.HasExited) { $daemon.Kill($true) }
    }
    $r = Complete-WtHintergrund $hinter 120
    Assert-Bedingung (Test-Path -LiteralPath $daemonMarke) '34' 'Vorbereitung: Das Gate hat keinen Hintergrundprozess gestartet' $r
    Assert-Bedingung $beendet '34' "integrate wartete auf das Ende des erbenden Hintergrundprozesses (nach $dauer s noch aktiv)" $r
    Assert-Wt $r 0 'OK' '34'
    Assert-Bedingung ((Get-Sha 'main') -eq (Get-Sha 'is-033-warten')) '34' 'main steht nicht auf dem Branch-Tip' $r

    Write-Output 'Fall 35: verwaister Gate-Prozess nach Abbruch von wt blockiert integrate und commit -Gate'
    Set-Datei (Join-Path $wt33 'src\n1.txt') "n1`n"
    New-GitCommit $wt33 'IS-033: n1.txt' @('src/n1.txt') | Out-Null
    $laeuft = Join-Path $testPath 'gate-laeuft.pid'
    $halten = Join-Path $testPath 'gate-halten.frei'
    $script:FreiMarken.Add($halten)
    $env:WT_SMOKE_LAEUFT = $laeuft
    $env:WT_SMOKE_HALTEN = $halten
    try {
        $hinter = Start-WtHintergrund $haupt @('integrate', '-Key', 'IS-033')
    } finally {
        $env:WT_SMOKE_LAEUFT = $null
        $env:WT_SMOKE_HALTEN = $null
    }
    if (-not (Wait-Datei $laeuft 60)) {
        throw 'Fall 35: Vorbereitung gescheitert – das Gate meldet sich nicht'
    }
    $gateSkriptProzess = Add-ProzessAusDatei $laeuft
    $inhaberPfad = Join-Path $common 'ai-sdlc\integration.owner'
    $gatePid = $null
    $uhr = [Diagnostics.Stopwatch]::StartNew()
    while (-not $gatePid -and $uhr.Elapsed.TotalSeconds -lt 10) {
        try { $gatePid = (Get-Content -LiteralPath $inhaberPfad -Raw | ConvertFrom-Json).gatePid } catch { }
        if (-not $gatePid) { Start-Sleep -Milliseconds 200 }
    }
    $gateProzess = if ($gatePid) { Add-ProzessNachPid ([int]$gatePid) } else { $null }
    Assert-Bedingung ($null -ne $gateProzess -and -not $gateProzess.HasExited) '35' `
        "integration.owner nennt keine laufende gatePid (gelesen: '$gatePid')"
    # wt hart beenden wie einen abgebrochenen Hintergrund-Task; ohne Gegenmaßnahme läuft das Gate weiter.
    try { $hinter.P.Kill() } catch { }
    [void]$hinter.P.WaitForExit(30000)
    Start-Sleep -Milliseconds 500
    $verwaist = ($null -ne $gateProzess -and -not $gateProzess.HasExited) -or
        ($null -ne $gateSkriptProzess -and -not $gateSkriptProzess.HasExited)
    if ($verwaist) {
        $mainAlt = Get-Sha 'main'
        $tip33 = Get-Sha 'is-033-warten'
        $zaehler = Get-Zaehler
        $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-033')
        Assert-Wt $r 12 'BLOCKIERT' '35'
        Assert-Bedingung ($r.WtZeile -match 'Gate-Prozess') '35' 'Die Meldung nennt den verwaisten Gate-Prozess nicht' $r
        Assert-Bedingung ((Get-Sha 'main') -eq $mainAlt -and (Get-Sha 'is-033-warten') -eq $tip33 -and (Get-Zaehler) -eq $zaehler) '35' `
            'Trotz verwaistem Gate wurden main, Branch oder Gate angefasst' $r
        # Auch nach dieser Blockade bleibt der verwaiste Prozess bekannt, und commit -Gate erkennt ihn ebenso.
        [IO.File]::WriteAllText($cHaupt, "c 1`nc 2 fix 4`nc 3`n")
        $kopf = Get-Sha 'HEAD'
        $r = Invoke-Wt $haupt @('commit', '-Nachricht', 'Fix: c.txt neben verwaistem Gate', '-Gate', 'src/c.txt')
        Assert-Wt $r 12 'BLOCKIERT' '35'
        Assert-Bedingung ($r.WtZeile -match 'Gate-Prozess') '35' 'commit -Gate nennt den verwaisten Gate-Prozess nicht' $r
        Assert-Bedingung ((Get-Sha 'HEAD') -eq $kopf -and (Get-Zaehler) -eq $zaehler) '35' 'commit -Gate hat trotz verwaistem Gate gegatet oder committet' $r
        Get-GitZeilen $haupt @('checkout', '-q', '--', 'src/c.txt') | Out-Null
    } else {
        Write-Output '  Hinweis: Das Gate endete zusammen mit wt; ein verwaister Gate-Prozess kann nicht entstehen.'
    }
    [IO.File]::WriteAllText($halten, 'frei')
    Assert-Bedingung (($null -eq $gateProzess -or $gateProzess.WaitForExit(60000)) -and
        ($null -eq $gateSkriptProzess -or $gateSkriptProzess.WaitForExit(60000))) '35' 'Der verwaiste Gate-Prozess endete nach der Freigabe nicht'
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-033')
    Assert-Wt $r 0 'OK' '35'
    Assert-Bedingung ((Get-Sha 'main') -eq (Get-Sha 'is-033-warten') -and (Test-Objekt 'main:src/n1.txt')) '35' 'main steht nicht auf dem Branch-Tip' $r

    Write-Output 'Fall 36: ff scheitert nach teilweisem Schreiben (gesperrte Datei im Hauptcheckout) – TEILZUSTAND'
    Set-Datei (Join-Path $haupt 'src\h2.txt') "h2 main`n"
    New-GitCommit $haupt 'main: h2.txt' @('src/h2.txt') | Out-Null
    Get-GitZeilen $wt33 @('merge', '-q', '--ff-only', 'main') | Out-Null
    Set-Datei (Join-Path $wt33 'src\h1.txt') "h1 aus dem Branch`n"
    Set-Datei (Join-Path $wt33 'src\h2.txt') "h2 aus dem Branch`n"
    New-GitCommit $wt33 'IS-033: h1 und h2' @('src/h1.txt', 'src/h2.txt') | Out-Null
    $mainAlt = Get-Sha 'main'
    # Git schreibt src/h1.txt vor src/h2.txt; die gesperrte h2.txt lässt sich nicht ersetzen.
    $gesperrt = Start-Halter -Ort $testPath -Datei (Join-Path $haupt 'src\h2.txt') -Teilen Read
    try {
        $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-033')
    } finally {
        Stop-Halter $gesperrt
    }
    $rest = @(Get-Aenderungen $haupt)
    Assert-Bedingung ($rest -contains '?? src/h1.txt') '36' "Vorbereitung: der ff hat nichts teilweise geschrieben (Status: $($rest -join ', '))" $r
    Assert-Wt $r 13 'TEILZUSTAND' '36'
    Assert-Bedingung ((Get-Sha 'main') -eq $mainAlt) '36' 'main hat sich verändert' $r
    Assert-Bedingung ($r.Text -match 'src[\\/]h1\.txt') '36' 'Die veränderten Pfade (src/h1.txt) werden nicht genannt' $r
    Remove-Item -LiteralPath (Join-Path $haupt 'src\h1.txt')
    Assert-Bedingung (@(Get-Aenderungen $haupt).Count -eq 0) '36' 'Hauptcheckout ließ sich nicht zurücksetzen'

    Write-Output 'Fall 37: Hilfe nennt beide Regeldateien; die WT-Zeile erscheint auch bei unterdrücktem Informationsstrom'
    $r = Invoke-Wt $haupt @('help')
    Assert-Wt $r 0 'OK' '37'
    Assert-Bedingung ($r.Text.Contains('~/.claude/ai-sdlc/arbeitsbaeume.md') -and $r.Text.Contains('~/.codex/ai-sdlc/arbeitsbaeume.md')) '37' `
        'Die Hilfe nennt nicht beide Regeldateien (Claude und Codex)' $r
    $r = Invoke-Wt $haupt @('status', '-InformationAction', 'Ignore')
    Assert-Bedingung (($r.Code -eq 0 -and $r.Status -ceq 'OK') -or ($r.Code -eq 1 -and $r.Status -ceq 'FEHLER')) '37' `
        "Ohne Informationsstrom fehlt die WT-Zeile oder passt nicht zum Exitcode (Exit $($r.Code), '$($r.WtZeile)')" $r

    # Fälle 38 und 39 teilen ein Submodul vendor/lib aus einem lokalen Wegwerf-Repo; im Hauptcheckout bleibt es
    # uninitialisiert (leerer Ordner), im Worktree wird es für den Hub initialisiert.
    Write-Output 'Fall 38: ein per .gitmodules (ignore = all) ausgeblendeter Submodul-Hub gilt bei der Nachweis-Ableitung als gate-relevant'
    $subRepo = Join-Path $testPath 'vendor-lib'
    New-Item -ItemType Directory -Path $subRepo | Out-Null
    Get-GitZeilen $subRepo @('init', '-q', '-b', 'main') | Out-Null
    Get-GitZeilen $subRepo @('config', 'user.name', 'WT Smoke') | Out-Null
    Get-GitZeilen $subRepo @('config', 'user.email', 'wt-smoke@example.invalid') | Out-Null
    Set-Datei (Join-Path $subRepo 'lib.txt') "lib 1`n"
    $subAlt = New-GitCommit $subRepo 'lib 1' @('lib.txt')
    Set-Datei (Join-Path $subRepo 'lib.txt') "lib 2`n"
    $subNeu = New-GitCommit $subRepo 'lib 2' @('lib.txt')
    $subUrl = $subRepo.Replace('\', '/')
    Set-Datei (Join-Path $haupt '.gitmodules') "[submodule `"vendor/lib`"]`n`tpath = vendor/lib`n`turl = $subUrl`n`tignore = all`n"
    New-Item -ItemType Directory -Force -Path (Join-Path $haupt 'vendor\lib') | Out-Null
    Get-GitZeilen $haupt @('update-index', '--add', '--cacheinfo', "160000,$subAlt,vendor/lib") | Out-Null
    Get-GitZeilen $haupt @('add', '--', '.gitmodules') | Out-Null
    Get-GitZeilen $haupt @('commit', '-q', '-m', 'vendor/lib als Submodul (ignore = all)') | Out-Null
    $r = Invoke-Wt $haupt @('start', '-Key', 'IS-038', '-Slug', 'submodul')
    Assert-Wt $r 0 'OK' '38'
    $wt38 = Join-Path $wtWurzel 'is-038'
    Set-Datei (Join-Path $wt38 'src\s.txt') "s`n"
    New-GitCommit $wt38 'IS-038: s.txt' @('src/s.txt') | Out-Null
    $zaehler = Get-Zaehler
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-038')
    Assert-Wt $r 0 'OK' '38'
    Assert-Bedingung ((Get-Zaehler) -eq $zaehler + 1) '38' 'Gate lief für die erste Einheit nicht genau einmal' $r
    $treeAlt = Get-Sha 'HEAD^{tree}' $wt38
    Get-GitZeilen $wt38 @('-c', 'protocol.file.allow=always', 'submodule', 'update', '-q', '--init', '--', 'vendor/lib') | Out-Null
    $subWt = Join-Path $wt38 'vendor\lib'
    Get-GitZeilen $subWt @('checkout', '-q', $subNeu) | Out-Null
    Get-GitZeilen $wt38 @('add', '--', 'vendor/lib') | Out-Null
    Get-GitZeilen $wt38 @('commit', '-q', '-m', 'IS-038: vendor/lib angehoben') | Out-Null
    if (@(Get-GitZeilen $wt38 @('diff', '--name-only', $treeAlt, (Get-Sha 'HEAD^{tree}' $wt38))).Count -ne 0 -or
        @(Get-GitZeilen $wt38 @('status', '--porcelain', '-uall', '--ignore-submodules=none')).Count -ne 0) {
        throw 'Fall 38: Vorbereitung gescheitert – ignore = all blendet den Hub nicht aus oder der Worktree ist nicht sauber'
    }
    $zaehler = Get-Zaehler
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-038')
    Assert-Wt $r 0 'OK' '38'
    Assert-Bedingung ((Get-Zaehler) -eq $zaehler + 1) '38' 'Der Submodul-Hub wurde ohne Gate-Lauf integriert (Nachweis abgeleitet)' $r
    Assert-Bedingung ((Get-Sha 'main') -eq (Get-Sha 'is-038-submodul')) '38' 'main steht nicht auf dem Branch-Tip' $r

    Write-Output 'Fall 39: finish mit initialisiertem Submodul – unsauber blockiert ohne Löschen, sauber wird entfernt'
    $subNotiz = Join-Path $subWt 'notiz-im-submodul.txt'
    Set-Datei $subNotiz "ungetrackt im Submodul`n"
    $r = Invoke-Wt $haupt @('finish', '-Key', 'IS-038')
    Assert-Wt $r 12 'BLOCKIERT' '39'
    Assert-Bedingung ((Test-Registriert $wt38) -and (Test-Path -LiteralPath $subNotiz) -and (Test-Zweig 'is-038-submodul')) '39' `
        'finish hat trotz unsauberem Submodul Worktree, Submodul-Datei oder Branch entfernt' $r
    Remove-Item -LiteralPath $subNotiz
    $r = Invoke-Wt $haupt @('finish', '-Key', 'IS-038')
    Assert-Wt $r 0 'OK' '39'
    Assert-Bedingung (-not (Test-Path -LiteralPath $wt38) -and -not (Test-Registriert $wt38) -and -not (Test-Zweig 'is-038-submodul')) '39' `
        'Worktree mit sauberem Submodul oder Branch is-038 nach finish noch vorhanden' $r
    Get-GitZeilen $haupt @('rm', '-q', '--cached', '--', 'vendor/lib') | Out-Null
    Get-GitZeilen $haupt @('rm', '-q', '--', '.gitmodules') | Out-Null
    Get-GitZeilen $haupt @('commit', '-q', '-m', 'vendor/lib entfernt') | Out-Null
    Remove-Item -LiteralPath (Join-Path $haupt 'vendor') -Recurse -Force -ErrorAction SilentlyContinue

    Write-Output 'Fall 40: commit -Gate – wird eine genannte Datei unmittelbar nach dem Gate geändert, committet wt die gegateten Bytes; die Änderung bleibt uncommittet'
    $gegatet40 = "c 1`nc 2 fix 40`nc 3`n"
    [IO.File]::WriteAllText($cHaupt, $gegatet40)
    if (Test-GateReste) { throw 'Fall 40: Vorbereitung gescheitert – unter worktreeRoot liegt schon ein _gate-Ordner' }
    # Der Schreiber wartet, bis der temporäre Gate-Worktree wieder verschwunden ist (Gate fertig), und schreibt sofort.
    $schreiber = Start-Schreiber -Modus NachGate -Werte @{ Wurzel = $wtWurzel; Datei = $cHaupt; Text = 'nach dem Gate geaendert' }
    $kopf = Get-Sha 'HEAD'
    $zaehler = Get-Zaehler
    $r = Invoke-Wt $haupt @('commit', '-Nachricht', 'Fix: Schreiber nach dem Gate', '-Gate', 'src/c.txt')
    $ergebnis = Complete-Schreiber $schreiber 20
    if ($ergebnis -cne 'geschrieben') {
        throw "Fall 40: Vorbereitung gescheitert – der Schreiber hat nicht nach dem Gate geschrieben ($ergebnis)$(Format-Ausgabe $r)"
    }
    Assert-Wt $r 0 'OK' '40'
    Assert-Bedingung ((Get-Sha 'HEAD~1') -eq $kopf -and (Test-Menge @(Get-CommitDateien $haupt) @('src/c.txt'))) '40' `
        'Es entstand nicht genau ein Commit mit src/c.txt' $r
    Assert-Bedingung ((Get-GitBlob $haupt 'HEAD:src/c.txt') -ceq $gegatet40) '40' 'Committet wurde nicht der gegatete Inhalt von src/c.txt' $r
    Assert-Bedingung ((Read-Text $cHaupt) -ceq "nach dem Gate geaendert`n") '40' 'Die Änderung nach dem Gate wurde überschrieben' $r
    $rest = @(Get-Aenderungen $haupt)
    Assert-Bedingung (Test-Menge $rest @(' M src/c.txt')) '40' `
        "Index steht nicht auf HEAD (Rückwärts-Diff) oder Status unerwartet: $($rest -join ', ')" $r
    Assert-Bedingung ((Get-Zaehler) -eq $zaehler + 1 -and -not (Test-GateReste)) '40' 'Gate lief nicht genau einmal oder der _gate-Worktree blieb' $r
    Get-GitZeilen $haupt @('checkout', '-q', '--', 'src/c.txt') | Out-Null

    Write-Output 'Fall 41: commit -Gate – Junctions im temporären und in verwaisten Gate-Worktrees werden entfernt, ohne ihren Zielen zu folgen'
    $kanSetup = New-Kanarie 'kanarie-setup'
    $kanVerwaist = New-Kanarie 'kanarie-verwaist'
    $kanRest = New-Kanarie 'kanarie-rest'
    # setup teilt einen Ordner per Junction (z. B. node_modules des Hauptcheckouts) und meldet das Anlegen.
    $setup41 = 'if ($env:WT_SMOKE_KANARIE) { New-Item -ItemType Junction -Path node_modules -Target $env:WT_SMOKE_KANARIE | Out-Null; ' +
        '[IO.File]::WriteAllText($env:WT_SMOKE_KANARIE + ''.angelegt'', (Get-Location).Path) }'
    Set-KonfigCommit (New-KonfigText @{ setup = $setup41 }) 'Konfig: setup mit Junction'
    $verwaist41 = Join-Path $wtWurzel '_gate-77777'
    Get-GitZeilen $haupt @('worktree', 'add', '-q', '--detach', $verwaist41, 'HEAD') | Out-Null
    New-Junction (Join-Path $verwaist41 'node_modules') $kanVerwaist.Pfad
    $rest41 = Join-Path $wtWurzel '_gate-66666'
    Set-Datei (Join-Path $rest41 'rest.txt') "rest`n"
    New-Junction (Join-Path $rest41 'node_modules') $kanRest.Pfad
    [IO.File]::WriteAllText($cHaupt, "c 1`nc 2 fix 41`nc 3`n")
    $kopf = Get-Sha 'HEAD'
    $zaehler = Get-Zaehler
    $angelegt41 = $kanSetup.Pfad + '.angelegt'
    $env:WT_SMOKE_KANARIE = $kanSetup.Pfad
    try {
        $r = Invoke-Wt $haupt @('commit', '-Nachricht', 'Fix: Gate mit geteiltem Ordner', '-Gate', 'src/c.txt')
    } finally {
        $env:WT_SMOKE_KANARIE = $null
    }
    if (-not (Test-Path -LiteralPath $angelegt41)) {
        throw "Fall 41: Vorbereitung gescheitert – setup hat im temporären Worktree keine Junction angelegt$(Format-Ausgabe $r)"
    }
    Assert-Wt $r 0 'OK' '41'
    Assert-Bedingung ((Get-Sha 'HEAD~1') -eq $kopf -and (Test-Menge @(Get-CommitDateien $haupt) @('src/c.txt'))) '41' `
        'Es entstand nicht genau ein Commit mit src/c.txt' $r
    Assert-Bedingung (Test-Kanarie $kanSetup) '41' 'Der Abbau des temporären Gate-Worktrees ist der Junction aus setup gefolgt' $r
    Assert-Bedingung (Test-Kanarie $kanVerwaist) '41' 'Das Aufräumen des verwaisten Gate-Worktrees _gate-77777 ist seiner Junction gefolgt' $r
    Assert-Bedingung (Test-Kanarie $kanRest) '41' 'Das Aufräumen des nicht registrierten Gate-Rests _gate-66666 ist seiner Junction gefolgt' $r
    Assert-Bedingung (-not (Test-GateReste)) '41' 'Ein temporärer oder verwaister _gate-Worktree bzw. Gate-Rest blieb' $r
    Reset-Konfig 'Konfig: setup wieder leer'
    Assert-Bedingung (@(Get-Aenderungen $haupt).Count -eq 0) '41' 'Hauptcheckout ist nach dem Fall nicht sauber'

    Write-Output 'Fall 42: pre-commit-Hook formatiert eine genannte Datei um – wt commit meldet den angelegten Commit eindeutig, commit -Gate committet die gegateten Bytes'
    $hook42 = Join-Path $common 'hooks\pre-commit'
    $hookInhalt = @'
#!/bin/sh
# Smoke-Hook fuer tests/wt-smoke.ps1: formatiert *.fmt.txt um und staget neu (Muster lint-staged)
for f in $(git diff --cached --name-only --diff-filter=ACM); do
  case "$f" in
    *.fmt.txt) printf 'vom Hook formatiert\n' > "$f"; git add -- "$f" ;;
  esac
done
exit 0
'@
    $fremd42 = Join-Path $haupt 'docs\fremd42.txt'
    Set-Datei $fremd42 "gestagt`n"
    Get-GitZeilen $haupt @('add', '--', 'docs/fremd42.txt') | Out-Null
    [IO.File]::WriteAllText($fremd42, "danach geaendert`n")
    $indexFremd = Get-GitWert $haupt @('ls-files', '-s', '--', 'docs/fremd42.txt')
    Set-Datei $hook42 ($hookInhalt -replace "`r`n", "`n")
    try {
        Set-Datei (Join-Path $haupt 'docs\hook42.fmt.txt') "roh 42`n"
        $kopf = Get-Sha 'HEAD'
        $r = Invoke-Wt $haupt @('commit', '-Nachricht', 'Doku: Hook formatiert', 'docs/hook42.fmt.txt')
        $neu = Get-Sha 'HEAD'
        if ($neu -eq $kopf -or (Get-GitBlob $haupt 'HEAD:docs/hook42.fmt.txt') -cne "vom Hook formatiert`n") {
            throw "Fall 42: Vorbereitung gescheitert – kein Commit oder der pre-commit-Hook lief nicht$(Format-Ausgabe $r)"
        }
        Assert-Wt $r 12 'BLOCKIERT' '42'
        Assert-Bedingung ((Get-Sha 'HEAD~1') -eq $kopf -and $r.WtZeile -match 'Hook' -and $r.WtZeile.Contains($neu.Substring(0, 7))) '42' `
            "Die Meldung nennt den angelegten Commit $($neu.Substring(0, 8)) und den Hook nicht eindeutig" $r
        Assert-Bedingung ($r.WtZeile -match 'hook42\.fmt\.txt') '42' 'Die Meldung nennt die vom Hook veränderte Datei nicht' $r
        $rest = @(Get-Aenderungen $haupt)
        Assert-Bedingung (Test-Menge $rest @('AM docs/fremd42.txt')) '42' `
            "Indexeintrag der genannten Datei steht nicht auf HEAD bzw. fremde Datei angefasst: $($rest -join ', ')" $r
        Assert-Bedingung ((Get-GitWert $haupt @('ls-files', '-s', '--', 'docs/fremd42.txt')) -ceq $indexFremd) '42' `
            'Der gestagte Stand der fremden Datei wurde verändert' $r
        # commit -Gate committet die gegateten Bytes (commit-tree); der Hook läuft dabei nicht
        Set-Datei (Join-Path $haupt 'docs\gate42.fmt.txt') "roh gate 42`n"
        $kopf = Get-Sha 'HEAD'
        $zaehler = Get-Zaehler
        $r = Invoke-Wt $haupt @('commit', '-Nachricht', 'Doku: Gate trotz Hook', '-Gate', 'docs/gate42.fmt.txt')
        Assert-Wt $r 0 'OK' '42'
        Assert-Bedingung ((Get-Sha 'HEAD~1') -eq $kopf -and (Test-Menge @(Get-CommitDateien $haupt) @('docs/gate42.fmt.txt'))) '42' `
            'Es entstand nicht genau ein Commit mit docs/gate42.fmt.txt' $r
        Assert-Bedingung ((Get-GitBlob $haupt 'HEAD:docs/gate42.fmt.txt') -ceq "roh gate 42`n") '42' `
            'commit -Gate hat nicht die gegateten Bytes committet (Ergebnis des Hooks?)' $r
        Assert-Bedingung ((Get-Zaehler) -eq $zaehler + 1) '42' 'Gate lief nicht genau einmal' $r
        $rest = @(Get-Aenderungen $haupt)
        Assert-Bedingung (Test-Menge $rest @('AM docs/fremd42.txt')) '42' "Nach commit -Gate unerwarteter Status: $($rest -join ', ')" $r
        Assert-Bedingung ((Get-GitWert $haupt @('ls-files', '-s', '--', 'docs/fremd42.txt')) -ceq $indexFremd) '42' `
            'commit -Gate hat den gestagten Stand der fremden Datei verändert' $r
    } finally {
        Remove-Item -LiteralPath $hook42 -Force -ErrorAction SilentlyContinue
    }
    Get-GitZeilen $haupt @('reset', '-q', '--', 'docs/fremd42.txt') | Out-Null
    Remove-Item -LiteralPath $fremd42

    Write-Output 'Fall 43: sync verweigert bei uncommittetem Issue-Ordner im Hauptcheckout; gescheiterter ff bei fremder Dateiaktivität ist kein TEILZUSTAND'
    $notiz43 = Join-Path $haupt 'issues\IS-022-ohne-wt\notiz.md'
    Set-Datei $notiz43 "uncommittete Neufreigabe`n"
    $kopf22 = Get-Sha 'HEAD' $wt22
    if (Test-Vorfahr 'main' $kopf22) { throw 'Fall 43: Vorbereitung gescheitert – is-022 enthält main schon, sync hätte nichts zu tun' }
    $r = Invoke-Wt $wt22 @('sync')
    Assert-Wt $r 12 'BLOCKIERT' '43'
    Assert-Bedingung ($r.WtZeile -match 'Issue-Ordner') '43' 'Die Meldung nennt den unsauberen Issue-Ordner nicht' $r
    Assert-Bedingung ((Get-Sha 'HEAD' $wt22) -eq $kopf22 -and @(Get-Aenderungen $wt22).Count -eq 0) '43' 'sync hat den Worktree trotz Blockade verändert' $r
    Assert-Bedingung ((Read-Text $notiz43) -ceq "uncommittete Neufreigabe`n") '43' 'Die uncommittete Datei im Issue-Ordner wurde verändert' $r
    Remove-Item -LiteralPath (Split-Path -Parent $notiz43) -Recurse -Force
    # main bewegt sich während des Gates (nur gate-irrelevant), der erste ff scheitert mit „Not possible to
    # fast-forward“; ab dem Ende des Gates legt eine andere Session im Hauptcheckout laufend neue Dateien an.
    $ende43 = Join-Path $testPath 'gate-ende-43.txt'
    $flutOrdner = Join-Path $haupt 'entwuerfe-andere-session'
    $flut = Start-Schreiber -Modus Flut -Werte @{ Start = $ende43; Ordner = $flutOrdner }
    Remove-Item -LiteralPath $marke -ErrorAction SilentlyContinue
    $zaehler = Get-Zaehler
    $env:WT_SMOKE_BEWEGEN = 'irrelevant'
    $env:WT_SMOKE_ENDE = $ende43
    try {
        $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-022')
    } finally {
        $env:WT_SMOKE_BEWEGEN = $null
        $env:WT_SMOKE_ENDE = $null
        [IO.File]::WriteAllText($flut.Stopp, 'stopp')
    }
    $angelegt43 = Complete-Schreiber $flut 20
    if (-not (Test-Path -LiteralPath $marke) -or $angelegt43 -notmatch '^\d+$' -or [int]$angelegt43 -lt 1) {
        throw "Fall 43: Vorbereitung gescheitert – main bewegte sich nicht während des Gates oder die andere Session legte keine Dateien an ($angelegt43)$(Format-Ausgabe $r)"
    }
    Assert-Wt $r 0 'OK' '43'
    Assert-Bedingung ((Get-Sha 'main') -eq (Get-Sha 'is-022-ohne-wt') -and (Test-Objekt 'main:src/neu22.txt')) '43' 'main steht nicht auf dem rebasten Branch-Tip' $r
    Assert-Bedingung ((Get-Zaehler) -eq $zaehler + 1) '43' "Gate lief $((Get-Zaehler) - $zaehler)-mal statt einmal" $r
    Remove-Item -LiteralPath $flutOrdner -Recurse -Force
    Assert-Bedingung (@(Get-Aenderungen $haupt).Count -eq 0) '43' 'Hauptcheckout ist nach dem Fall nicht sauber'

    Write-Output 'Fall 44: integrate liest die Projektwerte nach Erhalt der Integrationssperre neu (Konfiguration während des Wartens geändert)'
    $zaehler = Get-Zaehler
    $mainKonfig = ''
    $sperre = Start-Halter -Ort $testPath -Datei $integrationLock -Teilen None
    try {
        $hinter = Start-WtHintergrund $haupt @('integrate', '-Key', 'IS-033')
        if (-not (Wait-WtZeile $hinter 'warte.*Integrationssperre' 60)) {
            throw "Fall 44: Vorbereitung gescheitert – integrate wartet nicht auf die Integrationssperre: $($hinter.Zeilen -join ' | ')"
        }
        # während des Wartens: src/h1.txt (vom Branch geändert) gehört jetzt zu nurAufMain
        Set-KonfigCommit (New-KonfigText @{ nurAufMain = @('projektplan.md', 'src/h1.txt') }) 'Konfig: src/h1.txt nur auf main'
        $mainKonfig = Get-Sha 'main'
    } finally {
        Stop-Halter $sperre
    }
    $r = Complete-WtHintergrund $hinter 120
    Assert-Wt $r 12 'BLOCKIERT' '44'
    Assert-Bedingung ($r.WtZeile -match 'src/h1\.txt') '44' 'Die Meldung nennt die nach dem Warten verbotene Datei src/h1.txt nicht' $r
    Assert-Bedingung ((Get-Sha 'main') -eq $mainKonfig -and -not (Test-Objekt 'main:src/h1.txt') -and (Get-Zaehler) -eq $zaehler) '44' `
        'integrate arbeitete nach dem Warten mit den alten Projektwerten weiter (main oder Gate angefasst)' $r
    Reset-Konfig 'Konfig: nurAufMain wieder Standard'

    Write-Output 'Fall 45: doppelte Nummer als Altlast auf main – nur WARNUNG für unbeteiligte Branches und Korrekturen; eine vom Branch hinzugefügte Dublette blockiert'
    $altA = Join-Path $haupt 'docs\adr\ADR-0003-alt-a.md'
    $altB = Join-Path $haupt 'docs\adr\ADR-0003-alt-b.md'
    Set-Datei $altA "# ADR-0003 alt a`n"
    Set-Datei $altB "# ADR-0003 alt b`n"
    New-GitCommit $haupt 'Altlast: zweimal ADR-0003 (am Werkzeug vorbei)' @('docs/adr/ADR-0003-alt-a.md', 'docs/adr/ADR-0003-alt-b.md') | Out-Null
    $zaehler = Get-Zaehler
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-033')
    Assert-Wt $r 0 'OK' '45'
    Assert-Bedingung ((Get-Sha 'main') -eq (Get-Sha 'is-033-warten') -and (Test-Objekt 'main:src/h1.txt') -and (Get-Zaehler) -eq $zaehler + 1) '45' `
        'Der unbeteiligte Branch is-033 wurde nicht mit genau einem Gate-Lauf integriert' $r
    $hinweis = @($r.Text -split "`n" | Where-Object { $_ -notmatch '^WT: ' })
    Assert-Bedingung (@($hinweis | Where-Object { $_ -match 'WARNUNG' }).Count -ge 1 -and @($hinweis | Where-Object { $_ -match 'ADR-0003-alt' }).Count -ge 1) '45' `
        'integrate warnt nicht vor der Altlast-Dublette ADR-0003' $r
    [IO.File]::AppendAllText($altB, "Tippfehler korrigiert`n")
    $kopf = Get-Sha 'HEAD'
    $r = Invoke-Wt $haupt @('commit', '-Nachricht', 'Doku: Altlast-ADR korrigiert', 'docs/adr/ADR-0003-alt-b.md')
    Assert-Wt $r 0 'OK' '45'
    Assert-Bedingung ((Get-Sha 'HEAD~1') -eq $kopf -and (Test-Menge @(Get-CommitDateien $haupt) @('docs/adr/ADR-0003-alt-b.md'))) '45' `
        'Die Korrektur der Altlast-ADR wurde nicht committet' $r
    $hinweis = @($r.Text -split "`n" | Where-Object { $_ -notmatch '^WT: ' })
    Assert-Bedingung (@($hinweis | Where-Object { $_ -match 'WARNUNG' }).Count -ge 1 -and @($hinweis | Where-Object { $_ -match 'ADR-0003-alt' }).Count -ge 1) '45' `
        'commit im Hauptcheckout warnt nicht vor der Altlast-Dublette ADR-0003' $r
    # Der Branch fügt der Altlast-Gruppe einen Namen hinzu: neue Dublette
    Set-Datei (Join-Path $wt22 'docs\adr\ADR-0003-neu.md') "# ADR-0003 neu`n"
    New-GitCommit $wt22 'IS-022: ADR-0003' @('docs/adr/ADR-0003-neu.md') | Out-Null
    $mainAlt = Get-Sha 'main'
    $zaehler = Get-Zaehler
    $r = Invoke-Wt $haupt @('integrate', '-Key', 'IS-022')
    Assert-Wt $r 12 'BLOCKIERT' '45'
    Assert-Bedingung ($r.WtZeile -match '0003') '45' 'Die Meldung nennt die doppelte Nummer 0003 nicht' $r
    Assert-Bedingung ((Get-Sha 'main') -eq $mainAlt -and (Get-Zaehler) -eq $zaehler) '45' 'Trotz neuer Dublette wurden main oder Gate angefasst' $r
    Get-GitZeilen $wt22 @('reset', '-q', '--hard', 'HEAD~1') | Out-Null
    Get-GitZeilen $haupt @('rm', '-q', '-f', '--', 'docs/adr/ADR-0003-alt-a.md', 'docs/adr/ADR-0003-alt-b.md') | Out-Null
    Get-GitZeilen $haupt @('commit', '-q', '-m', 'Altlast ADR-0003 entfernt', '--', 'docs/adr/ADR-0003-alt-a.md', 'docs/adr/ADR-0003-alt-b.md') | Out-Null

    Write-Output 'Fall 46: Konfiguration – geänderter hauptbranch muss zum Hauptcheckout passen; Korrektur bei falscher oder ungültiger HEAD-Konfiguration per wt commit'
    # (1) Konfiguration mit hauptbranch, auf dem der Hauptcheckout nicht steht
    $vertippt = New-KonfigText @{ hauptbranch = 'mian' }
    Set-Datei $konfigPfad $vertippt
    $kopf = Get-Sha 'HEAD'
    $r = Invoke-Wt $haupt @('commit', '-Nachricht', 'Konfig: hauptbranch vertippt', '.ai-sdlc/arbeitsbaeume.json')
    Assert-Wt $r 12 'BLOCKIERT' '46'
    Assert-Bedingung ((Get-Sha 'HEAD') -eq $kopf -and (Read-Text $konfigPfad) -ceq $vertippt) '46' `
        'Die Konfiguration mit falschem hauptbranch wurde committet oder die Arbeitskopie verändert' $r
    # (2) steht der Tippfehler schon in HEAD, gelingt der Korrektur-Commit (Prüfung gegen die Arbeitskopie)
    Set-KonfigCommit $vertippt 'Konfig: hauptbranch vertippt (am Werkzeug vorbei)'
    Set-Datei $konfigPfad $konfigText
    $kopf = Get-Sha 'HEAD'
    $r = Invoke-Wt $haupt @('commit', '-Nachricht', 'Konfig: hauptbranch korrigiert', '.ai-sdlc/arbeitsbaeume.json')
    Assert-Wt $r 0 'OK' '46'
    Assert-Bedingung ((Get-Sha 'HEAD~1') -eq $kopf -and (Get-GitBlob $haupt 'HEAD:.ai-sdlc/arbeitsbaeume.json') -ceq $konfigText) '46' `
        'Der Korrektur-Commit der Konfiguration fehlt oder hat einen anderen Inhalt' $r
    # (3) ungültige Konfiguration in HEAD: status mit Standardwerten und WARNUNG (andere Befehle 1: Fall 29)
    Set-KonfigCommit (New-KonfigText @{ gateIrrelevant = @('docs/*.md') }) 'Konfig: ungültig (am Werkzeug vorbei)'
    $r = Invoke-Wt $haupt @('status')
    Assert-Wt $r 0 'OK' '46'
    Assert-Bedingung (Test-Zeile $r @('WARNUNG', 'Konfiguration|Projektwert|arbeitsbaeume')) '46' 'status warnt nicht vor der ungültigen Konfiguration in HEAD' $r
    Assert-Bedingung (Test-PfadInText $r.Text $wt22) '46' 'status mit Standardwerten nennt den Worktree is-022 nicht' $r
    # (4) Korrektur per wt commit im Hauptcheckout; danach arbeiten die Befehle wieder
    Set-Datei $konfigPfad $konfigText
    $kopf = Get-Sha 'HEAD'
    $r = Invoke-Wt $haupt @('commit', '-Nachricht', 'Konfig: repariert', '.ai-sdlc/arbeitsbaeume.json')
    Assert-Wt $r 0 'OK' '46'
    Assert-Bedingung ((Get-Sha 'HEAD~1') -eq $kopf -and (Get-GitBlob $haupt 'HEAD:.ai-sdlc/arbeitsbaeume.json') -ceq $konfigText) '46' `
        'Der Commit der reparierten Konfiguration fehlt oder hat einen anderen Inhalt' $r
    $r = Invoke-Wt $haupt @('sync', '-Key', 'IS-022')
    Assert-Wt $r 0 'OK' '46'
    Assert-Bedingung ((Get-Sha 'HEAD' $wt22) -eq (Get-Sha 'main') -and @(Get-Aenderungen $haupt).Count -eq 0) '46' `
        'Nach der Reparatur steht is-022 nicht auf main oder der Hauptcheckout ist nicht sauber' $r

    Write-Output 'Fall 47: worktreeRoot über eine Junction und gateAblage mit versionierten Dateien werden beim Laden abgelehnt'
    $linkZiel = Join-Path $testPath 'wt-link-ziel'
    New-Item -ItemType Directory -Force -Path (Join-Path $linkZiel 'baum') | Out-Null
    $link47 = Join-Path $haupt 'wt-link'
    New-Junction $link47 $linkZiel
    $anzahl = @(Get-WorktreeEintraege).Count
    try {
        # Junction als Zwischenkomponente bzw. als worktreeRoot selbst
        foreach ($wurzel in 'wt-link/baum', 'wt-link') {
            Set-KonfigCommit (New-KonfigText @{ worktreeRoot = $wurzel }) "Konfig: worktreeRoot $wurzel (Junction)"
            $r = Invoke-Wt $haupt @('start', '-Key', 'IS-047', '-Slug', 'junction')
            Assert-Wt $r 1 'FEHLER' '47'
            Assert-Bedingung ($r.WtZeile -match 'worktreeRoot') '47' "Die Meldung nennt worktreeRoot nicht ($wurzel)" $r
            Assert-Bedingung (@(Get-WorktreeEintraege).Count -eq $anzahl -and -not (Test-Zweig 'is-047-junction') -and
                @(Get-ChildItem -LiteralPath $linkZiel -Recurse -Force).Count -eq 1) '47' `
                "start hat trotz Junction ($wurzel) einen Worktree, Branch oder Ordner angelegt" $r
        }
    } finally {
        Reset-Konfig 'Konfig: worktreeRoot wieder Standard'
        if (Test-Path -LiteralPath $link47) { [IO.Directory]::Delete($link47, $false) }
    }
    $exclude = Get-GitWert $haupt @('rev-parse', '--path-format=absolute', '--git-path', 'info/exclude')
    Set-KonfigCommit (New-KonfigText @{ gateAblage = 'docs' }) 'Konfig: gateAblage mit versionierten Dateien'
    try {
        $r = Invoke-Wt $haupt @('start', '-Key', 'IS-047', '-Slug', 'ablage')
        Assert-Wt $r 1 'FEHLER' '47'
        Assert-Bedingung ($r.WtZeile -match 'gateAblage') '47' 'Die Meldung nennt gateAblage nicht' $r
        Assert-Bedingung (@(Get-WorktreeEintraege).Count -eq $anzahl -and -not (Test-Zweig 'is-047-ablage') -and
            @(Get-Content -LiteralPath $exclude | Where-Object { $_.Trim() -ceq '/docs/' }).Count -eq 0) '47' `
            'start hat trotz versionierter Gate-Ablage einen Worktree angelegt oder /docs/ in info/exclude eingetragen' $r
    } finally {
        Reset-Konfig 'Konfig: gateAblage wieder Standard'
    }
    Assert-Bedingung (@(Get-Aenderungen $haupt).Count -eq 0) '47' 'Hauptcheckout ist nach dem Fall nicht sauber'

    Write-Output 'Fall 48: Rest einer gescheiterten Belegungsprobe (<dir>.wt-probe-*) – finish, start und status raten zum Zurückbenennen statt zu prune'
    $probe48 = "$wt22.wt-probe-4711"
    Rename-Item -LiteralPath $wt22 -NewName (Split-Path -Leaf $probe48)
    try {
        $r = Invoke-Wt $haupt @('finish', '-Key', 'IS-022')
        Assert-Wt $r 12 'BLOCKIERT' '48'
        Assert-Bedingung ($r.WtZeile -match 'wt-probe-4711' -and $r.WtZeile -match 'benenn') '48' `
            'finish nennt den Probe-Ordner nicht oder rät nicht zum Zurückbenennen (statt zu git worktree prune)' $r
        Assert-Bedingung ((Test-Path -LiteralPath $probe48) -and (Test-Registriert $wt22) -and (Test-Zweig 'is-022-ohne-wt')) '48' `
            'finish hat Probe-Ordner, Registrierung oder Branch angetastet' $r
        $r = Invoke-Wt $haupt @('start', '-Key', 'IS-022')
        Assert-Wt $r 12 'BLOCKIERT' '48'
        Assert-Bedingung ($r.WtZeile -match 'wt-probe-4711' -and $r.WtZeile -match 'benenn') '48' `
            'start nennt den Probe-Ordner nicht oder rät nicht zum Zurückbenennen (statt zu git worktree prune)' $r
        Assert-Bedingung ((Test-Path -LiteralPath $probe48) -and -not (Test-Path -LiteralPath $wt22) -and (Test-Registriert $wt22)) '48' `
            'start hat Probe-Ordner oder Registrierung angetastet' $r
        $r = Invoke-Wt $haupt @('status')
        Assert-Wt $r 0 'OK' '48'
        Assert-Bedingung (Test-Zeile $r @('wt-probe-4711', 'benenn')) '48' 'status rät beim Probe-Ordner nicht zum Zurückbenennen' $r
    } finally {
        if ((Test-Path -LiteralPath $probe48) -and -not (Test-Path -LiteralPath $wt22)) {
            Rename-Item -LiteralPath $probe48 -NewName (Split-Path -Leaf $wt22)
        }
    }

    if ((Get-Zweig $haupt) -cne 'main' -or @(Get-Aenderungen $haupt).Count -ne 0) {
        throw 'Abschluss: Hauptcheckout steht am Ende nicht sauber auf main'
    }
    Write-Output 'wt-Smoke-Test: OK'
} finally {
    foreach ($name in $envNamen) { [Environment]::SetEnvironmentVariable($name, $envAlt[$name]) }
    Stop-Restprozesse
    if (Test-Path -LiteralPath $testPath) {
        $aufgeloest = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $testPath).Path)
        if (-not (Test-Testziel $aufgeloest)) {
            throw 'Testziel vor der Löschung nicht verifiziert'
        }
        $geloescht = $false
        foreach ($versuch in 1..3) {
            try {
                Remove-Item -LiteralPath $aufgeloest -Recurse -Force
                $geloescht = $true
                break
            } catch {
                Start-Sleep -Milliseconds 500
            }
        }
        if (-not $geloescht) {
            Write-Warning "Testwurzel ließ sich nicht vollständig löschen: $aufgeloest"
        }
    }
}
