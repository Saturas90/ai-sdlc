#Requires -Version 7
<#
wt.ps1 – Issue-Worktrees für parallele Sessions im ai-sdlc-Workflow (Arbeitsbaum-Modus).

Zweck: Legt je Issue einen Git-Worktree <worktreeRoot>/<key> auf Branch <key>-<slug> an, hält ihn auf dem
Stand des Hauptbranchs, committet nur explizite Dateilisten, integriert per Rebase → Prüfungen → Gate
(einmal je Tree) → Fast-Forward unter Sperren und räumt nach der Integration auf.
Regeln: ~/.claude/ai-sdlc/arbeitsbaeume.md (Claude Code, Abschnitte 6–7) bzw.
~/.codex/ai-sdlc/arbeitsbaeume.md (Codex). Projektwerte: .ai-sdlc/arbeitsbaeume.json, gelesen aus HEAD des
Hauptcheckouts (eine uncommittete Änderung blockiert; die Datei gehört immer zu nurAufMain). Ist sie in HEAD
ungültig, läuft nur status (Standardwerte, WARNUNG) und wt commit genau dieser Datei im Hauptcheckout.
commit -Gate committet genau die gegateten Bytes per commit-tree/update-ref; Git-Hooks laufen dabei nicht.
Vor jedem 'git worktree remove' entfernt wt Junctions/Symlinks im Worktree (nur die Links, ohne ihnen zu
folgen): git folgt unter Windows Junctions und leerte sonst deren Ziel.

Aufruf:
  pwsh -NoProfile -File wt.ps1 <befehl> [-Key K] [-Slug s] [-Nachricht m] [-Gate] [-Repo pfad] [dateien…]

Befehle:
  start -Key K [-Slug s]               Worktree anlegen (vorhandenen Branch anhängen und sync, sonst
                                       <key>-<slug> vom Hauptbranch), Pflichtdateien laut .worktreeinclude,
                                       Setup; vorhandenen Worktree wiederverwenden und sync
  sync [-Key K]                        Branch ohne eigene Commits per ff, sonst per Rebase auf den Hauptbranch
  integrate [-Key K]                   Integrationssperre → Rebase → Prüfungen → Gate → ff (Hauptcheckout-Sperre)
  commit -Nachricht m [-Gate] <dat…>   Pfadlisten-Commit im aktuellen Checkout (Pfade relativ zu dessen
                                       Wurzel); im Hauptcheckout unter Sperre; -Gate nur im Hauptcheckout
                                       (committet die gegateten Bytes per commit-tree, ohne Git-Hooks)
  finish -Key K                        aus dem Hauptcheckout, nur wenn integriert: Gate-Ablage sichern,
                                       Worktree und Branch entfernen
  status                               Worktrees (mit Pfad), Reste, Sperren, Branches ohne Worktree
  help                                 Kurzhilfe

  Ohne -Key gilt der Key des aktuellen Worktrees. -Repo: Startverzeichnis (Standard: aktuelles).
  Die letzte Ausgabezeile lautet WT: <STATUS> <details> (fehlt nur bei PowerShell-Bindungsfehlern, Exit 1).

Exitcodes: 0 OK · 1 FEHLER (Aufruf oder unerwartet) · 10 KONFLIKT · 11 ROT (Gate) · 12 BLOCKIERT ·
           13 TEILZUSTAND (ff-Merge, Belegungsprobe von finish, Index nach commit -Gate) ·
           14 NICHTS (nichts zu tun)
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)][string]$Befehl,
    [string]$Key,
    [string]$Slug,
    [string]$Nachricht,
    [switch]$Gate,
    [string]$Repo,
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Dateien
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
$ProgressPreference = 'SilentlyContinue'
$env:GIT_EDITOR = 'true'

class WtExit : System.Exception {
    [int]$Code
    [string]$Status
    WtExit([int]$code, [string]$status, [string]$details) : base($details) {
        $this.Code = $code
        $this.Status = $status
    }
}

$script:Utf8 = [System.Text.UTF8Encoding]::new($false)
$script:KeyMuster = '^[A-Za-z]+-[0-9]+$'
$script:SlugMuster = '^[a-z0-9]+(-[a-z0-9]+)*$'
$script:KonfigRel = '.ai-sdlc/arbeitsbaeume.json'
$script:PwshExe = $null
$script:StdHandlesGeschuetzt = $false
# Verzeichnis des Aufrufers: finish verweigert, wenn es im zu entfernenden Worktree liegt
$script:StartVerzeichnis = [Environment]::CurrentDirectory
$script:Gewarnt = [System.Collections.Generic.HashSet[string]]::new()
# Zusatz zur Schlusszeile eines Commits (z. B. uncommittet gebliebene Arbeitskopie nach commit -Gate)
$script:CommitZusatz = ''

# ---------------------------------------------------------------- Grundfunktionen

function Stop-Wt([int]$Code, [string]$Status, [string]$Details) {
    throw [WtExit]::new($Code, $Status, $Details)
}

function First($Werte) {
    $a = @($Werte)
    if ($a.Count -gt 0) { return [string]$a[0] }
    return ''
}

function Norm([string]$Pfad) {
    $f = [IO.Path]::GetFullPath($Pfad)
    $wurzel = [IO.Path]::GetPathRoot($f)
    if ($f.Length -gt $wurzel.Length) { $f = $f.TrimEnd('\', '/') }
    return $f
}

function Test-GleicherPfad([string]$A, [string]$B) {
    return [string]::Equals((Norm $A), (Norm $B), [StringComparison]::OrdinalIgnoreCase)
}

function Test-PfadUnter([string]$Pfad, [string]$Basis) {
    # $Pfad ist $Basis selbst oder liegt darunter
    $p = Norm $Pfad
    $b = Norm $Basis
    if ([string]::Equals($p, $b, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $p.StartsWith($b.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
}

function Kurz([string]$Sha) {
    if ($Sha.Length -gt 8) { return $Sha.Substring(0, 8) }
    return $Sha
}

function Invoke-Git([string]$Dir, [string[]]$GitArgs, [hashtable]$ExtraEnv = $null) {
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = 'git'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = $script:Utf8
    $psi.StandardErrorEncoding = $script:Utf8
    if ([IO.Directory]::Exists($Dir)) { $psi.WorkingDirectory = $Dir }
    # autoStash nie: fremde uncommittete Arbeit darf weder gestasht noch mit Konflikt zurückgeschrieben werden
    foreach ($a in @('-C', $Dir, '-c', 'core.quotepath=false', '-c', 'core.longpaths=true',
            '-c', 'rebase.autoStash=false', '-c', 'merge.autoStash=false')) { $psi.ArgumentList.Add($a) }
    foreach ($a in $GitArgs) { $psi.ArgumentList.Add($a) }
    $umgebung = $psi.Environment
    $umgebung['LC_ALL'] = 'C'
    $umgebung['GIT_EDITOR'] = 'true'
    $umgebung['GIT_TERMINAL_PROMPT'] = '0'
    # Dateinamen nie als Pathspec-Muster deuten (check-ignore kennt das nicht)
    if ($GitArgs -notcontains 'check-ignore') { $umgebung['GIT_LITERAL_PATHSPECS'] = '1' }
    $umgebung['GIT_OPTIONAL_LOCKS'] = '0'
    foreach ($n in @('GIT_DIR', 'GIT_WORK_TREE', 'GIT_INDEX_FILE', 'GIT_COMMON_DIR', 'GIT_PREFIX',
            'GIT_OBJECT_DIRECTORY', 'GIT_NAMESPACE', 'GIT_CEILING_DIRECTORIES')) {
        [void]$umgebung.Remove($n)
    }
    # gezielt gesetzt, z. B. GIT_INDEX_FILE für den temporären Index von commit -Gate
    if ($null -ne $ExtraEnv) { foreach ($n in $ExtraEnv.Keys) { $umgebung[$n] = [string]$ExtraEnv[$n] } }
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        $p.StandardInput.Close()
        $ausTask = $p.StandardOutput.ReadToEndAsync()
        $errTask = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit()
        $aus = $ausTask.GetAwaiter().GetResult()
        $err = $errTask.GetAwaiter().GetResult()
        $code = $p.ExitCode
    } finally {
        $p.Dispose()
    }
    $zeilen = @($aus -split "`n" | ForEach-Object { $_.TrimEnd("`r") } | Where-Object { $_ -ne '' })
    return [pscustomobject]@{ Code = $code; Out = $aus; Err = $err; Lines = $zeilen }
}

function Invoke-GitOk([string]$Dir, [string[]]$GitArgs, [hashtable]$ExtraEnv = $null) {
    $r = Invoke-Git $Dir $GitArgs $ExtraEnv
    if ($r.Code -ne 0) {
        Write-GitZeilen $r
        Stop-Wt 1 'FEHLER' ("git {0} fehlgeschlagen: {1}" -f ($GitArgs -join ' '), (Get-GitKurz $r))
    }
    return $r
}

function Invoke-GitMitWiederholung([string]$Dir, [string[]]$GitArgs, [string]$Was) {
    # wiederholt bei belegter index.lock bzw. Ref-Sperre (andere Session im geteilten Checkout); sonst Ergebnis
    for ($i = 0; ; $i++) {
        $r = Invoke-Git $Dir $GitArgs
        if ($r.Code -eq 0) { return $r }
        $text = $r.Out + "`n" + $r.Err
        if ($text -notmatch 'index\.lock|cannot lock ref') { return $r }
        if ($i -lt 3) {
            Write-Host "Git-Sperre belegt (index.lock bzw. Ref) bei $Was – neuer Versuch in 3 s"
            Start-Sleep -Seconds 3
            continue
        }
        Write-GitZeilen $r
        Stop-Wt 12 'BLOCKIERT' "Git-Sperre dauerhaft belegt ($Was): $(Get-GitKurz $r)"
    }
}

function Get-GitMeldungen($R) {
    foreach ($t in @($R.Err, $R.Out)) {
        foreach ($z in ($t -split "`n")) {
            $z = $z.TrimEnd("`r")
            if ($z.Trim() -eq '' -or $z.StartsWith('hint:')) { continue }
            $z
        }
    }
}

function Get-GitKurz($R) {
    $m = @(Get-GitMeldungen $R | Select-Object -First 2)
    $text = ($m | ForEach-Object { $_.Trim() }) -join ' | '
    if ($text.Length -gt 300) { $text = $text.Substring(0, 300) + ' …' }
    if (-not $text) { $text = "Exitcode $($R.Code)" }
    return $text
}

function Write-GitZeilen($R) {
    foreach ($z in @(Get-GitMeldungen $R | Select-Object -First 30)) { Write-Host "  $z" }
}

function Get-PwshExe {
    if ($script:PwshExe) { return $script:PwshExe }
    $c = Get-Command pwsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $c) { $script:PwshExe = $c.Source }
    elseif ([Environment]::ProcessPath) { $script:PwshExe = [Environment]::ProcessPath }
    else { Stop-Wt 1 'FEHLER' 'pwsh nicht gefunden' }
    return $script:PwshExe
}

# ---------------------------------------------------------------- Konfiguration

function ConvertTo-RelPfad([string]$Wert) {
    $p = $Wert.Trim().Replace('\', '/')
    while ($p.StartsWith('./')) { $p = $p.Substring(2) }
    return $p.TrimStart('/')
}

function Test-Muster([string]$Wert) { return $Wert.IndexOfAny([char[]]'*?[') -ge 0 }

function ConvertTo-TextListe($Wert, [string]$Name) {
    if ($null -eq $Wert) { return }
    if ($Wert -is [string]) { return $Wert }
    if ($Wert -is [System.Collections.IEnumerable] -and $Wert -isnot [System.Collections.IDictionary]) {
        foreach ($v in $Wert) {
            if ($v -isnot [string]) { Stop-Wt 1 'FEHLER' "Projektwert '$Name' muss eine Liste von Zeichenketten sein" }
            $v
        }
        return
    }
    Stop-Wt 1 'FEHLER' "Projektwert '$Name' muss eine Liste von Zeichenketten sein"
}

function Test-Zahl($Wert) {
    return ($Wert -is [int] -or $Wert -is [long] -or $Wert -is [double] -or $Wert -is [decimal] -or
        $Wert -is [System.Numerics.BigInteger])
}

function ConvertTo-Konfiguration($Text) {
    # $Text: Inhalt von .ai-sdlc/arbeitsbaeume.json oder $null (Standardwerte); prüft alle Werte
    $cfg = [ordered]@{
        hauptbranch          = 'main'
        worktreeRoot         = '.claude/worktrees'
        issueOrdner          = @('issues')
        setup                = ''
        gate                 = $null
        schnelleGates        = ''
        nurAufMain           = @('projektplan.md')
        nurAufMainAusnahmen  = @()
        gateIrrelevant       = @()
        nummernPruefung      = @([ordered]@{ ordner = 'docs/adr'; muster = '^ADR-(\d{4})-' })
        integrationsVersuche = 3
        sperreWartenMinuten  = 240
        gateAblage           = '.gate-logs'
    }
    if ($null -ne $Text) {
        $json = $null
        try {
            $json = ConvertFrom-Json -InputObject ([string]$Text).TrimStart([char]0xFEFF) -AsHashtable -Depth 20
        } catch {
            Stop-Wt 1 'FEHLER' "ungültiges JSON in $($script:KonfigRel): $($_.Exception.Message)"
        }
        if ($json -isnot [System.Collections.IDictionary]) {
            Stop-Wt 1 'FEHLER' "$($script:KonfigRel) enthält kein JSON-Objekt"
        }
        foreach ($k in @($json.Keys)) {
            if ($cfg.Contains($k)) { $cfg[$k] = $json[$k] }
        }
    }

    $hb = $cfg['hauptbranch']
    if ($hb -isnot [string] -or $hb -notmatch '^[^\s~^:?*\[\\]+$') { Stop-Wt 1 'FEHLER' "Projektwert 'hauptbranch' ungültig" }

    $wr = $cfg['worktreeRoot']
    if ($wr -isnot [string]) { Stop-Wt 1 'FEHLER' "Projektwert 'worktreeRoot' muss eine Zeichenkette sein" }
    $wr = (ConvertTo-RelPfad $wr).TrimEnd('/')
    if (-not $wr -or $wr -match '^[A-Za-z]:' -or @($wr -split '/') -contains '..' -or @($wr -split '/') -contains '.') {
        Stop-Wt 1 'FEHLER' "Projektwert 'worktreeRoot' muss ein relativer Pfad im Repo sein"
    }
    $cfg['worktreeRoot'] = $wr

    $ga = $cfg['gateAblage']
    if ($ga -isnot [string]) { Stop-Wt 1 'FEHLER' "Projektwert 'gateAblage' muss eine Zeichenkette sein" }
    $ga = (ConvertTo-RelPfad $ga).TrimEnd('/')
    $gaTeile = @($ga -split '/')
    if (-not $ga -or $ga -match '^[A-Za-z]:' -or $gaTeile -contains '..' -or $gaTeile -contains '.' -or
        $gaTeile -contains '' -or (Test-Muster $ga) -or $gaTeile[0] -ieq '.git') {
        Stop-Wt 1 'FEHLER' "Projektwert 'gateAblage' muss ein relativer Pfad im Repo sein (ohne * ? [)"
    }
    if (("$ga/").StartsWith("$wr/", [StringComparison]::OrdinalIgnoreCase) -or
        ("$wr/").StartsWith("$ga/", [StringComparison]::OrdinalIgnoreCase)) {
        Stop-Wt 1 'FEHLER' "Projektwert 'gateAblage' darf sich nicht mit 'worktreeRoot' überschneiden"
    }
    $cfg['gateAblage'] = $ga

    foreach ($n in @('setup', 'schnelleGates')) {
        if ($null -eq $cfg[$n]) { $cfg[$n] = '' }
        if ($cfg[$n] -isnot [string]) { Stop-Wt 1 'FEHLER' "Projektwert '$n' muss eine Zeichenkette sein" }
    }
    if ($null -ne $cfg['gate'] -and $cfg['gate'] -isnot [string]) { Stop-Wt 1 'FEHLER' "Projektwert 'gate' muss eine Zeichenkette sein" }
    if ($null -ne $cfg['gate']) { $cfg['gate'] = $cfg['gate'].Trim() }
    $cfg['setup'] = $cfg['setup'].Trim()

    foreach ($n in @('issueOrdner', 'nurAufMain', 'nurAufMainAusnahmen', 'gateIrrelevant')) {
        $cfg[$n] = [string[]]@(ConvertTo-TextListe $cfg[$n] $n | ForEach-Object { ConvertTo-RelPfad $_ } | Where-Object { $_ -ne '' })
    }
    # Muster würden wörtlich verglichen und Prüfungen still abschalten
    foreach ($n in @('nurAufMain', 'nurAufMainAusnahmen', 'gateIrrelevant')) {
        foreach ($e in $cfg[$n]) {
            if (Test-Muster $e) {
                Stop-Wt 1 'FEHLER' "Projektwert '$n': Eintrag '$e' enthält ein Muster (* ? [) – erlaubt sind feste Pfade und Ordner mit / am Ende"
            }
        }
    }

    $np = [System.Collections.Generic.List[object]]::new()
    if ($null -ne $cfg['nummernPruefung']) {
        $roh = $cfg['nummernPruefung']
        if ($roh -is [System.Collections.IDictionary]) { $roh = @($roh) }
        if ($roh -is [string] -or $roh -isnot [System.Collections.IEnumerable]) { Stop-Wt 1 'FEHLER' "Projektwert 'nummernPruefung' muss eine Liste sein" }
        foreach ($e in $roh) {
            if ($e -isnot [System.Collections.IDictionary] -or $e['ordner'] -isnot [string] -or $e['muster'] -isnot [string]) {
                Stop-Wt 1 'FEHLER' "Projektwert 'nummernPruefung': jeder Eintrag braucht 'ordner' und 'muster'"
            }
            $rx = $null
            try { $rx = [regex]::new($e['muster']) } catch { Stop-Wt 1 'FEHLER' "Projektwert 'nummernPruefung': ungültiges Muster '$($e['muster'])'" }
            if ($rx.GetGroupNumbers().Count -lt 2) {
                Stop-Wt 1 'FEHLER' "Projektwert 'nummernPruefung': Muster '$($e['muster'])' braucht mindestens eine Fanggruppe für die Nummer"
            }
            $np.Add([pscustomobject]@{ ordner = (ConvertTo-RelPfad $e['ordner']).TrimEnd('/'); muster = $e['muster']; regex = $rx })
        }
    }
    $cfg['nummernPruefung'] = $np.ToArray()

    $iv = $cfg['integrationsVersuche']
    if (-not (Test-Zahl $iv) -or [double]$iv -lt 1 -or [double]$iv -ne [math]::Floor([double]$iv)) {
        Stop-Wt 1 'FEHLER' "Projektwert 'integrationsVersuche' muss eine ganze Zahl ≥ 1 sein"
    }
    $cfg['integrationsVersuche'] = [int]$iv
    $sw = $cfg['sperreWartenMinuten']
    if (-not (Test-Zahl $sw) -or [double]$sw -lt 0) { Stop-Wt 1 'FEHLER' "Projektwert 'sperreWartenMinuten' muss eine Zahl ≥ 0 sein" }
    $cfg['sperreWartenMinuten'] = [double]$sw
    return [pscustomobject]$cfg
}

function Test-KonfigImRepo($Cfg, [string]$Haupt) {
    # Prüfungen beim Laden, die das Repo brauchen; liefert die Fehlermeldung oder $null
    $pfad = $Haupt
    foreach ($teil in @($Cfg.worktreeRoot -split '/')) {
        $pfad = Join-Path $pfad $teil
        $attr = $null
        try { $attr = [IO.File]::GetAttributes($pfad) } catch { break }
        # git registriert den aufgelösten Pfad; wt verglich mit dem Link-Pfad, status hielte Worktrees für Reste
        if ($attr -band [IO.FileAttributes]::ReparsePoint) {
            return "Projektwert 'worktreeRoot': worktreeRoot darf keine Junction/kein Symlink sein ('$teil' in $($Cfg.worktreeRoot))"
        }
    }
    # info/exclude nähme sonst versionierte Ordner aus git status, die Sauberkeitsprüfungen übergingen sie
    $lt = Invoke-Git $Haupt @('ls-tree', '--name-only', 'HEAD', '--', $Cfg.gateAblage)
    if ($lt.Code -eq 0 -and @($lt.Lines).Count) {
        return "Projektwert 'gateAblage': '$($Cfg.gateAblage)' enthält in HEAD versionierte Dateien – einen eigenen, nicht versionierten Ordner wählen"
    }
    return $null
}

function Read-Konfiguration([string]$Haupt, [switch]$Leise) {
    # Quelle ist HEAD des Hauptcheckouts; eine abweichende Arbeitskopie wirkt nicht, sondern blockiert (12).
    # Ist der Stand in HEAD ungültig, gelten Standardwerte und Fehler ist gesetzt: dann laufen nur status und der
    # Commit genau dieser Datei im Hauptcheckout (Invoke-Wt, Invoke-CmdCommit).
    $rel = $script:KonfigRel
    $text = $null
    $abweichung = $false
    if ((Invoke-Git $Haupt @('cat-file', '-e', "HEAD:$rel")).Code -eq 0) {
        $r = Invoke-Git $Haupt @('show', "HEAD:$rel")
        if ($r.Code -ne 0) { Stop-Wt 1 'FEHLER' "Konfiguration aus HEAD nicht lesbar: $(Get-GitKurz $r)" }
        $text = $r.Out
        $abweichung = @((Invoke-GitOk $Haupt @('status', '--porcelain', '--ignore-submodules=none', '--', $rel)).Lines).Count -gt 0
    } elseif (Test-Path -LiteralPath (Join-Path $Haupt $rel) -PathType Leaf) {
        $text = [IO.File]::ReadAllText((Join-Path $Haupt $rel))
        if (-not $Leise) {
            Write-Host "WARNUNG: Konfiguration nicht versioniert – $rel fehlt in HEAD des Hauptcheckouts; verwendet wird die Arbeitskopie (per wt commit festschreiben)"
        }
    }
    $cfg = $null
    $fehler = $null
    try {
        $cfg = ConvertTo-Konfiguration $text
        $fehler = Test-KonfigImRepo $cfg $Haupt
    } catch [WtExit] {
        $fehler = $_.Exception.Message
    }
    if ($fehler) { $cfg = ConvertTo-Konfiguration $null }
    return [pscustomobject]@{ Cfg = $cfg; Abweichung = $abweichung; Fehler = $fehler; Text = $text }
}

function Read-KonfigArbeitskopie([string]$Haupt) {
    # Commit der Konfigurationsdatei: die Arbeitskopie vollständig prüfen (fehlt sie, gelten Standardwerte)
    $p = Join-Path $Haupt $script:KonfigRel
    $text = $null
    if (Test-Path -LiteralPath $p -PathType Leaf) { $text = [IO.File]::ReadAllText($p) }
    $cfg = $null
    $fehler = $null
    try {
        $cfg = ConvertTo-Konfiguration $text
        $fehler = Test-KonfigImRepo $cfg $Haupt
    } catch [WtExit] {
        $fehler = $_.Exception.Message
    }
    if ($fehler) { Stop-Wt 1 'FEHLER' "Arbeitskopie von $($script:KonfigRel) ungültig – nichts committet: $fehler" }
    return $cfg
}

function Get-KonfigFuerKonfigCommit($Ctx, $Kq) {
    # Commit der Konfigurationsdatei im Hauptcheckout: Hauptbranch-Prüfung gegen den Wert der (geprüften)
    # Arbeitskopie; sonst gelten die Werte aus HEAD, bei ungültigem HEAD die der Arbeitskopie
    $wc = Read-KonfigArbeitskopie $Ctx.Main
    if ($Kq.Fehler) { return $wc }
    $cfg = $Kq.Cfg.PSObject.Copy()
    $cfg.hauptbranch = $wc.hauptbranch
    return $cfg
}

function Set-KontextKonfig($Ctx, $Cfg) {
    $Ctx.Cfg = $Cfg
    $Ctx.RootDir = Norm (Join-Path $Ctx.Main $Cfg.worktreeRoot)
}

function Update-KontextKonfig($Ctx) {
    # nach Erhalt der Integrationssperre und zu Beginn jedes Versuchs: Projektwerte neu aus HEAD lesen, damit ein
    # während des Wartens committeter Stand gilt
    $kq = Read-Konfiguration $Ctx.Main -Leise
    if ($Ctx.KonfigCommit) {
        $cfg = Get-KonfigFuerKonfigCommit $Ctx $kq
    } else {
        if ($kq.Fehler) { Stop-Wt 1 'FEHLER' "Konfiguration in HEAD inzwischen ungültig: $($kq.Fehler)" }
        $Ctx.KonfigAbweichung = $kq.Abweichung
        Assert-KonfigUnveraendert $Ctx
        $cfg = $kq.Cfg
    }
    if ($kq.Text -cne $Ctx.KonfigText) {
        Write-Host 'Hinweis: Projektwerte in HEAD haben sich seit dem Start geändert – es gelten die neuen Werte'
        $Ctx.KonfigText = $kq.Text
    }
    Set-KontextKonfig $Ctx $cfg
}

function Assert-KonfigUnveraendert($Ctx) {
    if ($Ctx.KonfigAbweichung) {
        Stop-Wt 12 'BLOCKIERT' "Konfiguration uncommittet geändert: $($script:KonfigRel) im Hauptcheckout weicht von HEAD ab – per wt commit festschreiben oder zurücknehmen"
    }
}

# ---------------------------------------------------------------- Kontext

function Get-Worktrees([string]$Dir) {
    $r = Invoke-GitOk $Dir @('worktree', 'list', '--porcelain')
    $liste = [System.Collections.Generic.List[object]]::new()
    $cur = $null
    foreach ($roh in ($r.Out -split "`n")) {
        $z = $roh.TrimEnd("`r")
        if ($z.StartsWith('worktree ')) {
            if ($null -ne $cur) { $liste.Add($cur) }
            $cur = [pscustomobject]@{ Path = (Norm $z.Substring(9)); Head = ''; Branch = ''; Detached = $false
                Bare = $false; Locked = $false; Prunable = $false }
            continue
        }
        if ($null -eq $cur -or $z -eq '') { continue }
        if ($z.StartsWith('HEAD ')) { $cur.Head = $z.Substring(5) }
        elseif ($z.StartsWith('branch ')) {
            $b = $z.Substring(7)
            if ($b.StartsWith('refs/heads/')) { $b = $b.Substring(11) }
            $cur.Branch = $b
        }
        elseif ($z -eq 'detached') { $cur.Detached = $true }
        elseif ($z -eq 'bare') { $cur.Bare = $true }
        elseif ($z.StartsWith('locked')) { $cur.Locked = $true }
        elseif ($z.StartsWith('prunable')) { $cur.Prunable = $true }
    }
    if ($null -ne $cur) { $liste.Add($cur) }
    return $liste.ToArray()
}

function Get-Kontext {
    $start = if ($Repo) { $Repo } else { (Get-Location).ProviderPath }
    if (-not (Test-Path -LiteralPath $start -PathType Container)) { Stop-Wt 1 'FEHLER' "Verzeichnis nicht gefunden: $start" }
    $start = (Resolve-Path -LiteralPath $start).ProviderPath
    $top = Invoke-Git $start @('rev-parse', '--show-toplevel')
    if ($top.Code -ne 0 -or -not (First $top.Lines)) { Stop-Wt 1 'FEHLER' "kein Git-Arbeitsverzeichnis: $start" }
    $common = Norm (First (Invoke-GitOk $start @('rev-parse', '--path-format=absolute', '--git-common-dir')).Lines)
    $wts = @(Get-Worktrees $start)
    if ($wts.Count -eq 0 -or $wts[0].Bare) { Stop-Wt 1 'FEHLER' 'Bare-Repository wird nicht unterstützt' }
    $haupt = $wts[0].Path
    $kq = Read-Konfiguration $haupt
    $cfg = $kq.Cfg
    $topN = Norm (First $top.Lines)
    return [pscustomobject]@{
        Top              = $topN
        Main             = $haupt
        Common           = $common
        IsMain           = (Test-GleicherPfad $topN $haupt)
        Cfg              = $cfg
        KonfigAbweichung = $kq.Abweichung
        KonfigFehler     = $kq.Fehler
        KonfigText       = $kq.Text
        KonfigCommit     = $false
        RootDir          = (Norm (Join-Path $haupt $cfg.worktreeRoot))
        LockDir          = (Join-Path $common 'ai-sdlc')
        Worktrees        = $wts
    }
}

function Resolve-Key($Ctx) {
    if ($Key) {
        if ($Key -notmatch $script:KeyMuster) { Stop-Wt 1 'FEHLER' "ungültiger Key '$Key' (Muster BUCHSTABEN-ZIFFERN, z. B. ISSUE-0256)" }
        return $Key.ToLowerInvariant()
    }
    if ($Ctx.IsMain) { Stop-Wt 1 'FEHLER' 'im Hauptcheckout ist -Key erforderlich' }
    $eltern = Norm (Split-Path -Parent $Ctx.Top)
    $blatt = Split-Path -Leaf $Ctx.Top
    if ((Test-GleicherPfad $eltern $Ctx.RootDir) -and $blatt -match $script:KeyMuster) { return $blatt.ToLowerInvariant() }
    Stop-Wt 1 'FEHLER' "Key nicht bestimmbar: $($Ctx.Top) liegt nicht direkt unter $($Ctx.RootDir); -Key angeben"
}

function Get-WtDir($Ctx, [string]$K) { return (Norm (Join-Path $Ctx.RootDir $K)) }

function Find-Worktree($Ctx, [string]$Dir) {
    foreach ($w in $Ctx.Worktrees) { if (Test-GleicherPfad $w.Path $Dir) { return $w } }
    return $null
}

function Get-AktuellerBranch([string]$Dir) {
    $r = Invoke-Git $Dir @('symbolic-ref', '-q', 'HEAD')
    if ($r.Code -ne 0) { return '' }
    $ref = First $r.Lines
    if ($ref.StartsWith('refs/heads/')) { return $ref.Substring(11) }
    return ''
}

function Assert-HauptAufHauptbranch($Ctx) {
    $hb = $Ctx.Cfg.hauptbranch
    $aktuell = Get-AktuellerBranch $Ctx.Main
    if ($aktuell -cne $hb) {
        $zeige = if ($aktuell) { $aktuell } else { '(detached HEAD)' }
        Stop-Wt 12 'BLOCKIERT' "Hauptcheckout steht auf '$zeige' statt auf '$hb'"
    }
}

function Get-GitDir([string]$Dir) { return (Norm (First (Invoke-GitOk $Dir @('rev-parse', '--absolute-git-dir')).Lines)) }

function Get-OffeneOperationen([string]$Dir) {
    $gd = Get-GitDir $Dir
    if ((Test-Path -LiteralPath (Join-Path $gd 'rebase-merge')) -or (Test-Path -LiteralPath (Join-Path $gd 'rebase-apply'))) { 'REBASE' }
    if (Test-Path -LiteralPath (Join-Path $gd 'MERGE_HEAD')) { 'MERGE' }
    if (Test-Path -LiteralPath (Join-Path $gd 'CHERRY_PICK_HEAD')) { 'CHERRY-PICK' }
    if (Test-Path -LiteralPath (Join-Path $gd 'REVERT_HEAD')) { 'REVERT' }
}

function Assert-KeineOperation([string]$Dir, [string]$Was) {
    $ops = @(Get-OffeneOperationen $Dir)
    if ($ops.Count) {
        Stop-Wt 12 'BLOCKIERT' ("{0}: offene Operation {1} – Stand lesen, vor 'rebase --abort' den Menschen fragen" -f $Was, ($ops -join '/'))
    }
}

function Get-StatusZeilen([string]$Dir, [string]$Ablage = '') {
    # mit $Ablage: ungetrackte Einträge der Gate-Ablage zählen nicht (Sauberkeitsprüfungen)
    $r = Invoke-GitOk $Dir @('status', '--porcelain', '-uall', '--ignore-submodules=none')
    $praefix = if ($Ablage) { $Ablage.TrimEnd('/') + '/' } else { '' }
    foreach ($z in $r.Lines) {
        if ($praefix -and $z.StartsWith('?? ') -and
            $z.Substring(3).TrimStart('"').StartsWith($praefix, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $z
    }
}

function Assert-Sauber([string]$Dir, [string]$Was, [string]$Ablage = '') {
    $z = @(Get-StatusZeilen $Dir $Ablage)
    if ($z.Count) {
        Write-Host "$Was hat uncommittete Änderungen:"
        $z | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
        Stop-Wt 12 'BLOCKIERT' "$Was nicht sauber ($($z.Count) Einträge)"
    }
}

function Get-Anzahl([string]$Dir, [string]$Bereich) {
    return [int](First (Invoke-GitOk $Dir @('rev-list', '--count', $Bereich)).Lines)
}

function Test-PfadTreffer([string]$Pfad, [string[]]$Eintraege) {
    $p = (ConvertTo-RelPfad $Pfad)
    foreach ($e in @($Eintraege)) {
        if (-not $e) { continue }
        if ($e.EndsWith('/')) {
            if ($p.StartsWith($e, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        } elseif ([string]::Equals($p, $e, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Get-NurAufMainVerstoesse($Cfg, [string[]]$Pfade) {
    foreach ($p in @($Pfade)) {
        # die Konfiguration gehört immer dazu (auch ohne Eintrag, ohne Ausnahme): ein Branch brächte sonst
        # ungeprüfte Projektwerte nach main
        if ([string]::Equals((ConvertTo-RelPfad $p), $script:KonfigRel, [StringComparison]::OrdinalIgnoreCase)) { $p; continue }
        if ((Test-PfadTreffer $p $Cfg.nurAufMain) -and -not (Test-PfadTreffer $p $Cfg.nurAufMainAusnahmen)) { $p }
    }
}

function Find-KeyBranches($Ctx, [string]$K) {
    $r = Invoke-GitOk $Ctx.Main @('for-each-ref', '--format=%(refname)', 'refs/heads/')
    foreach ($ref in $r.Lines) {
        $b = $ref.Substring(11)
        if ($b -ceq $Ctx.Cfg.hauptbranch) { continue }
        if ([string]::Equals($b, $K, [StringComparison]::OrdinalIgnoreCase) -or
            $b.StartsWith("$K-", [StringComparison]::OrdinalIgnoreCase)) { $b }
    }
}

function Write-WarnungEinmal([string]$Text) {
    # dieselbe WARNUNG nur einmal je Lauf (Prüfungen laufen z. B. vor dem Gate und unter der Sperre)
    if ($script:Gewarnt.Add($Text)) { Write-Host $Text }
}

function Get-Dubletten($Np, [string[]]$Namen, $Genannt) {
    # "ordner: nummer (a, b)" je Nummer mit mehreren Einträgen; mit $Genannt nur Gruppen mit einem genannten Eintrag
    $gruppen = [System.Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($blatt in @($Namen)) {
        $m = $Np.regex.Match($blatt)
        if (-not $m.Success -or $m.Groups.Count -lt 2 -or -not $m.Groups[1].Success) { continue }
        $wert = $m.Groups[1].Value
        if (-not $gruppen.ContainsKey($wert)) { $gruppen[$wert] = [System.Collections.Generic.List[string]]::new() }
        $gruppen[$wert].Add($blatt)
    }
    foreach ($wert in $gruppen.Keys) {
        $g = $gruppen[$wert]
        if ($g.Count -lt 2) { continue }
        if ($null -ne $Genannt -and -not @($g | Where-Object { $Genannt.Contains($_) }).Count) { continue }
        "{0}: {1} ({2})" -f $Np.ordner, $wert, ($g -join ', ')
    }
}

function Assert-KeineMergeCommits([string]$Dir, [string]$Hb, [string]$Tip, [string]$Name) {
    # ein Rebase ohne --rebase-merges verwirft still, was nur im Merge-Commit steckt; ein ff übernähme ihn nach main
    $m = @((Invoke-GitOk $Dir @('rev-list', '--merges', "refs/heads/$Hb..$Tip")).Lines)
    if ($m.Count) {
        Write-Host "Merge-Commits in $Name (Rebase würde ihren Inhalt verwerfen):"
        $m | Select-Object -First 10 | ForEach-Object { Write-Host "  $_" }
        Stop-Wt 12 'BLOCKIERT' ("Merge-Commit im Branch {0} ({1}) – Branch linearisieren, Mensch" -f $Name, $m.Count)
    }
}

# ---------------------------------------------------------------- Sperren

function Get-InhaberDaten([string]$InhaberPfad) {
    try {
        if (-not (Test-Path -LiteralPath $InhaberPfad -PathType Leaf)) { return $null }
        $o = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($InhaberPfad)) -AsHashtable
        if ($o -is [System.Collections.IDictionary]) { return $o }
    } catch { }
    return $null
}

function Get-InhaberText([string]$InhaberPfad) {
    $o = Get-InhaberDaten $InhaberPfad
    if ($null -eq $o) { return 'unbekannt' }
    $t = "PID {0}, Key {1}, seit {2}, Rechner {3}" -f $o['pid'], $o['key'], $o['zeit'], $o['rechner']
    if ($o['gatePid']) { $t += ", Gate-PID $($o['gatePid'])" }
    return $t
}

function Lock-Datei([string]$Pfad, [double]$WartenSek, [string]$Name, [string]$InhaberPfad) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Pfad))
    $uhr = [Diagnostics.Stopwatch]::StartNew()
    $naechsteMeldung = 0.0
    while ($true) {
        try {
            return [IO.File]::Open($Pfad, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        } catch [System.IO.IOException] {
            # belegt – weiter warten
        }
        $sek = $uhr.Elapsed.TotalSeconds
        if ($sek -ge $naechsteMeldung) {
            if ($InhaberPfad) { Write-Host "warte auf Integrationssperre (Inhaber: $(Get-InhaberText $InhaberPfad))" }
            else { Write-Host "warte auf $Name" }
            $naechsteMeldung += 60
        }
        if ($sek -ge $WartenSek) {
            $inh = if ($InhaberPfad) { " (Inhaber: $(Get-InhaberText $InhaberPfad))" } else { '' }
            Stop-Wt 12 'BLOCKIERT' ("{0} nach {1} min Wartezeit noch belegt{2}" -f $Name, [math]::Round($WartenSek / 60, 2), $inh)
        }
        Start-Sleep -Milliseconds 500
    }
}

function Write-Inhaber([string]$InhaberPfad, [string]$Was) {
    $o = [ordered]@{ pid = $PID; key = $Was; zeit = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz'); rechner = [Environment]::MachineName }
    [IO.File]::WriteAllText($InhaberPfad, ($o | ConvertTo-Json -Compress), $script:Utf8)
}

function Set-InhaberGate([string]$InhaberPfad, $Prozess) {
    # Gate-Prozess vermerken: stirbt wt, erkennt der nächste Lauf ein noch laufendes Gate
    $o = Get-InhaberDaten $InhaberPfad
    if ($null -eq $o) { $o = [ordered]@{ pid = $PID } }
    $o['gatePid'] = $Prozess.Id
    $ticks = 0
    try { $ticks = $Prozess.StartTime.ToUniversalTime().Ticks } catch { }
    $o['gateStartTicks'] = $ticks
    [IO.File]::WriteAllText($InhaberPfad, ($o | ConvertTo-Json -Compress), $script:Utf8)
}

function Clear-InhaberGate([string]$InhaberPfad) {
    $o = Get-InhaberDaten $InhaberPfad
    if ($null -eq $o -or -not $o.Contains('gatePid')) { return }
    [void]$o.Remove('gatePid')
    [void]$o.Remove('gateStartTicks')
    [IO.File]::WriteAllText($InhaberPfad, ($o | ConvertTo-Json -Compress), $script:Utf8)
}

function Test-ProzessLaeuft($ProzessId, $StartTicks) {
    $id = 0
    if (-not [int]::TryParse([string]$ProzessId, [ref]$id) -or $id -le 0) { return $false }
    $p = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($null -eq $p) { return $false }
    $soll = 0L
    if (-not [long]::TryParse([string]$StartTicks, [ref]$soll) -or $soll -le 0) { return $true }
    try {
        # gleiche PID, andere Startzeit: wiederverwendete PID, nicht das Gate
        return ([math]::Abs($p.StartTime.ToUniversalTime().Ticks - $soll) -lt 20000000)
    } catch {
        return $false
    }
}

function Assert-KeinVerwaistesGate([string]$InhaberPfad) {
    $o = Get-InhaberDaten $InhaberPfad
    if ($null -eq $o -or -not $o['gatePid']) { return }
    if (Test-ProzessLaeuft $o['gatePid'] $o['gateStartTicks']) {
        Stop-Wt 12 'BLOCKIERT' ("verwaister Gate-Prozess läuft noch (PID {0}; gestartet von wt-PID {1}, Key {2}) – abwarten oder Prozessbaum beenden, Mensch" -f $o['gatePid'], $o['pid'], $o['key'])
    }
}

function Unlock-Integration($Sperre) {
    # integration.owner bleibt als Nachweis des letzten Inhabers; belegt ist die Sperre nur, solange die Datei offen ist
    if ($null -ne $Sperre) { $Sperre.Dispose() }
}

function Get-SperrStatus([string]$Pfad) {
    # nur lesend öffnen: ein mit FileShare.None gehaltener Lock verweigert auch Leser
    if (-not (Test-Path -LiteralPath $Pfad -PathType Leaf)) { return 'frei' }
    try {
        $fs = [IO.File]::Open($Pfad, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
        $fs.Dispose()
        return 'frei'
    } catch [System.UnauthorizedAccessException] {
        return 'unbekannt'
    } catch [System.IO.FileNotFoundException] {
        return 'frei'
    } catch [System.IO.DirectoryNotFoundException] {
        return 'frei'
    } catch [System.IO.IOException] {
        return 'belegt'
    }
}

# ---------------------------------------------------------------- Dateien, Logs, Befehle

function Add-Ignoriert($Ctx, [string]$Rel, [string[]]$AuchIn = @()) {
    # fehlt der Ignore-Eintrag im Hauptcheckout oder in einem der Worktrees aus $AuchIn (dort gilt deren älterer
    # .gitignore-Stand), /<rel>/ in info/exclude ergänzen – die Datei gilt für alle Worktrees
    $orte = [System.Collections.Generic.List[string]]::new()
    foreach ($d in @($Ctx.Main) + @($AuchIn)) {
        if (-not $d -or -not (Test-Path -LiteralPath $d -PathType Container)) { continue }
        if (@($orte | Where-Object { Test-GleicherPfad $_ $d }).Count) { continue }
        $orte.Add($d)
    }
    $fehlt = ''
    foreach ($d in $orte) {
        $r = Invoke-Git $d @('check-ignore', '-q', '--', "$Rel/")
        if ($r.Code -eq 0) { continue }
        if ($r.Code -ne 1) { Stop-Wt 1 'FEHLER' "git check-ignore fehlgeschlagen: $(Get-GitKurz $r)" }
        $fehlt = $d
        break
    }
    if (-not $fehlt) { return }
    $ex = Norm (First (Invoke-GitOk $Ctx.Main @('rev-parse', '--path-format=absolute', '--git-path', 'info/exclude')).Lines)
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($ex))
    $vor = ''
    if ((Test-Path -LiteralPath $ex -PathType Leaf) -and (Get-Item -LiteralPath $ex).Length -gt 0) {
        $inhalt = [IO.File]::ReadAllText($ex)
        if (@($inhalt -split "`r?`n" | Where-Object { $_.Trim() -ceq "/$Rel/" }).Count) {
            # Eintrag vorhanden, wirkt aber nicht (z. B. Negation in einer .gitignore)
            Write-WarnungEinmal "WARNUNG: /$Rel/ steht in $ex, ist in $fehlt aber nicht ignoriert (Negation in einer .gitignore?)"
            return
        }
        if (-not $inhalt.EndsWith("`n")) { $vor = "`n" }
    }
    [IO.File]::AppendAllText($ex, "$vor/$Rel/`n", $script:Utf8)
    Write-Host "WARNUNG: /$Rel/ war in $fehlt nicht ignoriert; in $ex ergänzt (gilt für alle Worktrees). Besser in die versionierte .gitignore aufnehmen (Build-Werkzeuge lesen info/exclude nicht)."
}

function Initialize-GateLogDir($Ctx, [string]$Wurzel) {
    # legt die Gate-Ablage in $Wurzel an und sorgt dafür, dass sie im Hauptcheckout und dort ignoriert ist
    $dir = Join-Path $Wurzel $Ctx.Cfg.gateAblage
    [void][IO.Directory]::CreateDirectory($dir)
    Add-Ignoriert $Ctx $Ctx.Cfg.gateAblage @($Wurzel)
    return $dir
}

function New-LogPfad([string]$Dir, [string]$Praefix) {
    $stempel = Get-Date -Format 'yyyyMMdd-HHmmss'
    $p = Join-Path $Dir "$Praefix-$stempel.log"
    $i = 2
    while (Test-Path -LiteralPath $p) { $p = Join-Path $Dir "$Praefix-$stempel-$i.log"; $i++ }
    return $p
}

function Stop-Prozessbaum($Prozess) {
    # beendet den Prozess samt Kindern (Abbruch von wt während Gate oder Setup)
    try {
        if ($Prozess.HasExited) { return }
        $tk = Join-Path ([Environment]::GetFolderPath('System')) 'taskkill.exe'
        if (-not (Test-Path -LiteralPath $tk -PathType Leaf)) { $tk = 'taskkill.exe' }
        $psi = [System.Diagnostics.ProcessStartInfo]::new($tk)
        foreach ($a in @('/T', '/F', '/PID', [string]$Prozess.Id)) { $psi.ArgumentList.Add($a) }
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $k = [System.Diagnostics.Process]::Start($psi)
        [void]$k.StandardOutput.ReadToEndAsync()
        [void]$k.StandardError.ReadToEndAsync()
        [void]$k.WaitForExit(15000)
        $k.Dispose()
        if (-not $Prozess.WaitForExit(5000)) { $Prozess.Kill($true) }
    } catch {
        try { if (-not $Prozess.HasExited) { $Prozess.Kill($true) } } catch { }
        # ein danach noch laufendes Gate meldet der nächste Lauf (gatePid)
    }
}

function Disable-StdHandleVererbung {
    # Gate und Setup sollen die Standard-Handles von wt nicht erben: Ein vom Gate gestarteter Hintergrundprozess
    # hielte sonst die Ausgabe-Pipe des Aufrufers offen, und wer bis EOF liest, wartete auf dessen Ende.
    if ($script:StdHandlesGeschuetzt) { return }
    $script:StdHandlesGeschuetzt = $true
    if (-not $IsWindows) { return }
    try {
        $typ = Add-Type -Namespace WtNative -Name StdHandles -PassThru -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern System.IntPtr GetStdHandle(int nStdHandle);
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true)]
public static extern bool SetHandleInformation(System.IntPtr hObject, uint dwMask, uint dwFlags);
'@
        foreach ($n in @(-10, -11, -12)) {
            $h = $typ::GetStdHandle($n)
            if ($h -ne [IntPtr]::Zero -and $h -ne [IntPtr]::new(-1)) { [void]$typ::SetHandleInformation($h, 1, 0) }
        }
    } catch {
        # ohne Schutz weiter; wt selbst wartet trotzdem nur auf das Prozessende
    }
}

function Read-ProzessAusgabe($Prozess, $Schreiber) {
    # liest stdout/stderr zeilenweise ins Log bis zum Prozessende; hält ein Kindprozess die Ausgabe offen,
    # endet das Lesen kurz nach dem Prozessende statt beim EOF
    $aus = $Prozess.StandardOutput
    $fehler = $Prozess.StandardError
    $tAus = $aus.ReadLineAsync()
    $tFehler = $fehler.ReadLineAsync()
    $nachlauf = $null
    while ($null -ne $tAus -or $null -ne $tFehler) {
        $neu = $false
        if ($null -ne $tAus -and $tAus.IsCompleted) {
            $z = $null
            try { $z = $tAus.GetAwaiter().GetResult() } catch { $z = $null }
            if ($null -eq $z) { $tAus = $null } else { $Schreiber.WriteLine($z); $tAus = $aus.ReadLineAsync() }
            $neu = $true
        }
        if ($null -ne $tFehler -and $tFehler.IsCompleted) {
            $z = $null
            try { $z = $tFehler.GetAwaiter().GetResult() } catch { $z = $null }
            if ($null -eq $z) { $tFehler = $null } else { $Schreiber.WriteLine($z); $tFehler = $fehler.ReadLineAsync() }
            $neu = $true
        }
        # Nachlauf auch dann begrenzen, wenn ein Kindprozess ununterbrochen weiterschreibt
        if ($Prozess.HasExited) {
            if ($null -eq $nachlauf) { $nachlauf = [Diagnostics.Stopwatch]::StartNew() }
            elseif ($nachlauf.Elapsed.TotalSeconds -ge 3) {
                if ($null -ne $tAus -or $null -ne $tFehler) {
                    $Schreiber.WriteLine('[wt] Prozess beendet; ein Kindprozess hält die Ausgabe offen – Rest nicht gelesen')
                }
                return
            }
        }
        if ($neu) { continue }
        $offen = [System.Threading.Tasks.Task[]]@(@($tAus, $tFehler) | Where-Object { $null -ne $_ })
        [void][System.Threading.Tasks.Task]::WaitAny($offen, 200)
    }
}

function Invoke-Befehlszeile([string]$Dir, [string]$Befehlszeile, [string]$LogPfad, [string]$InhaberPfad = '') {
    # Jeder scheiternde Schritt macht rot: Fehler beenden, ein Exitcode ≠ 0 eines nativen Befehls ist ein Fehler.
    $befehl = '$ErrorActionPreference=''Stop''; $PSNativeCommandUseErrorActionPreference=$true; ' + $Befehlszeile.Trim()
    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = Get-PwshExe
    foreach ($a in @('-NoProfile', '-Command', $befehl)) { $psi.ArgumentList.Add($a) }
    $psi.WorkingDirectory = $Dir
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $script:Utf8
    $psi.StandardErrorEncoding = $script:Utf8
    Disable-StdHandleVererbung
    $schreiber = [System.IO.StreamWriter]::new($LogPfad, $false, $script:Utf8)
    $schreiber.AutoFlush = $true
    $p = $null
    $fertig = $false
    try {
        $p = [System.Diagnostics.Process]::Start($psi)
        if ($InhaberPfad) { Set-InhaberGate $InhaberPfad $p }
        try { $p.StandardInput.Close() } catch { }
        Read-ProzessAusgabe $p $schreiber
        while (-not $p.WaitForExit(250)) { }
        $fertig = $true
        return [int]$p.ExitCode
    } finally {
        if ($null -ne $p) {
            if (-not $fertig) { Stop-Prozessbaum $p }
            $beendet = $true
            try { $beendet = $p.HasExited } catch { }
            if ($InhaberPfad -and $beendet) { try { Clear-InhaberGate $InhaberPfad } catch { } }
            $p.Dispose()
        }
        $schreiber.Dispose()
    }
}

function Show-LogEnde([string]$LogPfad) {
    Write-Host "--- letzte 40 Zeilen aus $LogPfad"
    if (Test-Path -LiteralPath $LogPfad -PathType Leaf) {
        Get-Content -LiteralPath $LogPfad -Tail 40 -Encoding utf8 | ForEach-Object { Write-Host $_ }
    }
    Write-Host '---'
}

function Copy-OrdnerFehlend([string]$Quelle, [string]$Ziel) {
    # kopiert nur fehlende Dateien (nie überschreiben); liefert die Anzahl kopierter Dateien
    if ((Test-Path -LiteralPath $Ziel) -and -not (Test-Path -LiteralPath $Ziel -PathType Container)) { return 0 }
    $anzahl = 0
    [void][IO.Directory]::CreateDirectory($Ziel)
    foreach ($d in @(Get-ChildItem -LiteralPath $Quelle -Recurse -Directory -Force)) {
        [void][IO.Directory]::CreateDirectory((Join-Path $Ziel ([IO.Path]::GetRelativePath($Quelle, $d.FullName))))
    }
    foreach ($f in @(Get-ChildItem -LiteralPath $Quelle -Recurse -File -Force)) {
        $zielDatei = Join-Path $Ziel ([IO.Path]::GetRelativePath($Quelle, $f.FullName))
        if (Test-Path -LiteralPath $zielDatei) { continue }
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName((Norm $zielDatei)))
        Copy-Item -LiteralPath $f.FullName -Destination $zielDatei
        $anzahl++
    }
    return $anzahl
}

function Copy-WorktreeInclude($Ctx, [string]$Ziel) {
    # kopiert fehlende gitignorierte Pflichtdateien laut .worktreeinclude; überschreibt nie
    $liste = Join-Path $Ctx.Main '.worktreeinclude'
    if (-not (Test-Path -LiteralPath $liste -PathType Leaf)) { return }
    foreach ($roh in [IO.File]::ReadAllLines($liste)) {
        $z = $roh.Trim()
        if (-not $z -or $z.StartsWith('#')) { continue }
        $rel = (ConvertTo-RelPfad $z).TrimEnd('/')
        if (-not $rel -or $rel -match '^[A-Za-z]:' -or @($rel -split '/') -contains '..') {
            Write-Host "Hinweis: .worktreeinclude-Eintrag '$z' ungültig – übersprungen"
            continue
        }
        if (Test-Muster $rel) {
            Write-Host "Hinweis: .worktreeinclude-Eintrag '$z' ist ein Muster; nur feste Pfade werden kopiert – übersprungen"
            continue
        }
        $quelle = Join-Path $Ctx.Main $rel
        if (-not (Test-Path -LiteralPath $quelle)) { Write-Host "Hinweis: $rel fehlt im Hauptcheckout – übersprungen"; continue }
        $istOrdner = Test-Path -LiteralPath $quelle -PathType Container
        $frage = if ($istOrdner) { "$rel/" } else { $rel }
        if ((Invoke-Git $Ctx.Main @('check-ignore', '-q', '--', $frage)).Code -ne 0) {
            Write-Host "Hinweis: $rel ist nicht gitignoriert – nicht kopiert"
            continue
        }
        # eigener Name: PowerShell unterscheidet bei Variablen keine Groß-/Kleinschreibung ($ziel wäre $Ziel)
        $zielPfad = Join-Path $Ziel $rel
        if ($istOrdner) {
            $anzahl = Copy-OrdnerFehlend $quelle $zielPfad
            if ($anzahl -gt 0) { Write-Host "kopiert (.worktreeinclude): $rel/ ($anzahl Datei(en))" }
            continue
        }
        if (Test-Path -LiteralPath $zielPfad) { continue }
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName((Norm $zielPfad)))
        Copy-Item -LiteralPath $quelle -Destination $zielPfad
        Write-Host "kopiert (.worktreeinclude): $rel"
    }
}

function Invoke-Setup($Ctx, [string]$Dir, [string]$LogDir, [string]$InhaberPfad = '') {
    $setup = $Ctx.Cfg.setup
    if (-not $setup) { return }
    $log = New-LogPfad $LogDir 'wt-setup'
    Write-Host "Setup läuft in $Dir (Log: $log)"
    $code = Invoke-Befehlszeile $Dir $setup $log $InhaberPfad
    if ($code -ne 0) {
        Show-LogEnde $log
        Stop-Wt 12 'BLOCKIERT' "Setup fehlgeschlagen (Exitcode $code); Worktree bleibt: $Dir; Log: $log"
    }
}

function ConvertTo-SicherName([string]$Name) { return ($Name -replace '[\\/:*?"<>|]', '_') }

function Get-InhaltsHash([byte[]]$Bytes) {
    return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes))
}

function Get-DateiHash([string]$Pfad) { return (Get-FileHash -LiteralPath $Pfad -Algorithm SHA256).Hash }

# ---------------------------------------------------------------- Rebase, Gate, ff

function Invoke-RebaseSchritt([string]$WtDir, [string]$Hb, [string]$Was) {
    $hbRef = "refs/heads/$Hb"
    $alteBasis = First (Invoke-GitOk $WtDir @('merge-base', $hbRef, 'HEAD')).Lines
    $alterTip = First (Invoke-GitOk $WtDir @('rev-parse', 'HEAD')).Lines
    $hbSha = First (Invoke-GitOk $WtDir @('rev-parse', $hbRef)).Lines
    if ($alteBasis -eq $hbSha) {
        Write-Host "$Was enthält $Hb bereits – kein Rebase nötig"
        return $false
    }
    Assert-KeineMergeCommits $WtDir $Hb 'HEAD' $Was
    $r = Invoke-Git $WtDir @('-c', 'rerere.enabled=true', '-c', 'rebase.updateRefs=false', 'rebase', '--no-autostash', $hbRef)
    $offen = @(Get-OffeneOperationen $WtDir) -contains 'REBASE'
    if ($r.Code -eq 0 -and -not $offen) {
        Write-Host "Rebase von $Was auf $Hb ($(Kurz $hbSha)) erfolgreich"
        return $true
    }
    if (-not $offen) {
        Write-GitZeilen $r
        Stop-Wt 12 'BLOCKIERT' "Rebase von $Was auf $Hb nicht möglich: $(Get-GitKurz $r)"
    }
    $dateien = @((Invoke-Git $WtDir @('diff', '--name-only', '--diff-filter=U', '--ignore-submodules=none', '--no-ext-diff')).Lines)
    $ab = Invoke-Git $WtDir @('rebase', '--abort')
    if ($ab.Code -ne 0 -or (@(Get-OffeneOperationen $WtDir) -contains 'REBASE')) {
        Write-GitZeilen $ab
        Stop-Wt 12 'BLOCKIERT' "Rebase von $Was hielt an und ließ sich nicht abbrechen – offener Rebase im Worktree, Mensch"
    }
    $tipNach = First (Invoke-Git $WtDir @('rev-parse', 'HEAD')).Lines
    if ($tipNach -ne $alterTip -or (Get-AktuellerBranch $WtDir) -cne $Was) {
        Stop-Wt 12 'BLOCKIERT' "nach 'rebase --abort' steht $Was nicht mehr auf $(Kurz $alterTip) – Stand prüfen, Mensch"
    }
    Write-Host "Konflikt beim Rebase von $Was auf $Hb – Rebase abgebrochen, Branch unverändert"
    if ($dateien.Count) {
        Write-Host 'Konfliktdateien:'
        $dateien | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host 'Konfliktdateien: keine offene (Rebase hielt ohne Konfliktdatei an, z. B. durch rerere) – gilt als Konflikt'
    }
    Write-Host "ALTE_BASIS=$alteBasis"
    Write-Host "ALTER_TIP=$alterTip"
    Stop-Wt 10 'KONFLIKT' ("Rebase von {0} auf {1}: {2} Konfliktdatei(en)" -f $Was, $Hb, $dateien.Count)
}

function Write-GateNachweis([string]$Dir, [string]$Tree, [string]$Commit, [string]$Branch, $Log, $AbgeleitetVon) {
    [void][IO.Directory]::CreateDirectory($Dir)
    $o = [ordered]@{ tree = $Tree; commit = $Commit; branch = $Branch; zeit = (Get-Date).ToString('yyyy-MM-ddTHH:mm:sszzz')
        log = $Log; abgeleitetVon = $AbgeleitetVon }
    [IO.File]::WriteAllText((Join-Path $Dir "$Tree.ok"), ($o | ConvertTo-Json), $script:Utf8)
}

function Set-LetzterTree([string]$Pfad, [string]$Tree) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Pfad))
    [IO.File]::WriteAllText($Pfad, "$Tree`n", $script:Utf8)
}

function Get-NachweisLog([string]$Pfad) {
    try {
        if (Test-Path -LiteralPath $Pfad -PathType Leaf) {
            return (ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($Pfad)) -AsHashtable)['log']
        }
    } catch { }
    return $null
}

function Invoke-IntegrationsGate($Ctx, [string]$WtDir, [string]$Branch, [string]$Sha, [string]$InhaberPfad) {
    $cfg = $Ctx.Cfg
    if ($cfg.gate -eq '') { Write-Host 'keine Gate-Kette (Projektwert leer)'; return }
    $tree = First (Invoke-GitOk $WtDir @('rev-parse', 'HEAD^{tree}')).Lines
    $gatesDir = Join-Path $Ctx.LockDir 'gates'
    $okPfad = Join-Path $gatesDir "$tree.ok"
    $letzterPfad = Join-Path $gatesDir ('letzter-' + (ConvertTo-SicherName $Branch) + '.txt')
    if (Test-Path -LiteralPath $okPfad -PathType Leaf) {
        Write-Host "Gate-Nachweis für Tree $(Kurz $tree) vorhanden – kein Neulauf"
        Set-LetzterTree $letzterPfad $tree
        return
    }
    if (Test-Path -LiteralPath $letzterPfad -PathType Leaf) {
        $alt = ([IO.File]::ReadAllText($letzterPfad)).Trim()
        if ($alt -match '^[0-9a-f]{40,64}$') {
            $d = Invoke-Git $WtDir @('diff', '--name-only', '--no-renames', '--ignore-submodules=none', '--no-ext-diff', '--no-relative', $alt, $tree)
            if ($d.Code -eq 0) {
                $alle = @($d.Lines)
                $relevant = @($alle | Where-Object { -not (Test-PfadTreffer $_ $cfg.gateIrrelevant) })
                if ($alle.Count -eq 0 -and $alt -ne $tree) {
                    # verschiedene Trees ohne sichtbaren Unterschied: nichts ableiten
                    Write-Host "Gate-Neulauf: Tree $(Kurz $tree) weicht von Tree $(Kurz $alt) ab, der Diff ist aber leer"
                } elseif ($relevant.Count -eq 0) {
                    Write-GateNachweis $gatesDir $tree $Sha $Branch (Get-NachweisLog (Join-Path $gatesDir "$alt.ok")) $alt
                    Set-LetzterTree $letzterPfad $tree
                    Write-Host ("seit gegatetem Tree {0} nur gate-irrelevante Änderungen ({1} Pfade) – Nachweis abgeleitet, kein Neulauf" -f (Kurz $alt), $alle.Count)
                    return
                } else {
                    Write-Host ("Gate-Neulauf: {0} gate-relevante Pfade seit Tree {1}" -f $relevant.Count, (Kurz $alt))
                }
            }
        }
    }
    # Der Nachweis gilt dem HEAD-Tree; deshalb unmittelbar vor dem Gate ein sauberer Arbeitsbaum
    $vorher = @(Get-StatusZeilen $WtDir $cfg.gateAblage)
    if ($vorher.Count) {
        Write-Host 'Worktree vor dem Gate nicht sauber:'
        $vorher | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
        Stop-Wt 12 'BLOCKIERT' "Worktree vor dem Gate nicht sauber ($($vorher.Count) Einträge) – kein Gate, keine Integration"
    }
    $logDir = Initialize-GateLogDir $Ctx $WtDir
    $log = New-LogPfad $logDir 'wt-gate'
    Write-Host "Gate läuft im Worktree auf Tree $(Kurz $tree) (Log: $log)"
    $code = Invoke-Befehlszeile $WtDir $cfg.gate $log $InhaberPfad
    $headNach = First (Invoke-GitOk $WtDir @('rev-parse', 'HEAD')).Lines
    $nachher = @(Get-StatusZeilen $WtDir $cfg.gateAblage)
    $veraendert = ($headNach -ne $Sha) -or ($nachher.Count -gt 0)
    if ($code -ne 0) {
        Show-LogEnde $log
        if ($veraendert) { Write-Host 'Hinweis: Das Gate hat außerdem HEAD oder den Arbeitsbaum verändert.' }
        Stop-Wt 11 'ROT' "Gate rot (Exitcode $code); Log: $log"
    }
    if ($veraendert) {
        if ($headNach -ne $Sha) { Write-Host "HEAD vorher $(Kurz $Sha), nachher $(Kurz $headNach)" }
        $nachher | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
        Stop-Wt 12 'BLOCKIERT' 'Gate hat HEAD oder den Arbeitsbaum verändert – kein Nachweis, keine Integration'
    }
    Write-GateNachweis $gatesDir $tree $Sha $Branch $log $null
    Set-LetzterTree $letzterPfad $tree
    Write-Host "Gate grün; Nachweis für Tree $(Kurz $tree) geschrieben"
}

function Show-HauptStatus($Ctx) {
    $r = Invoke-Git $Ctx.Main @('status', '--porcelain', '--ignore-submodules=none')
    Write-Host 'git status --porcelain (Hauptcheckout):'
    $r.Lines | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
    if (@($r.Lines).Count -gt 20) { Write-Host "  … ($(@($r.Lines).Count) Einträge)" }
}

function Get-HauptZustand($Ctx, $Pfade) {
    # HEAD und die Statuseinträge der Pfade, die der ff schreiben würde (andere Sessions ändern den
    # Hauptcheckout gleichzeitig; ihre Dateien sind kein Teilzustand)
    $h = Invoke-Git $Ctx.Main @('rev-parse', '-q', '--verify', 'HEAD')
    $s = Invoke-Git $Ctx.Main @('status', '--porcelain', '-z', '-uall', '--ignore-submodules=none')
    $eintraege = [System.Collections.Generic.List[string]]::new()
    $teile = $s.Out.Split([char]0)
    for ($i = 0; $i -lt $teile.Count; $i++) {
        $e = $teile[$i]
        if ($e.Length -lt 4) { continue }
        $xy = $e.Substring(0, 2)
        $hier = @($e.Substring(3))
        # Umbenennung/Kopie: im -z-Format folgt der alte Pfad als eigenes Feld
        if ($xy.Contains('R') -or $xy.Contains('C')) { $i++; if ($i -lt $teile.Count) { $hier += $teile[$i] } }
        if (@($hier | Where-Object { $Pfade.Contains($_) }).Count) { $eintraege.Add("$xy $($hier -join ' <- ')") }
    }
    return [pscustomobject]@{ Head = (First $h.Lines); Status = [string[]]$eintraege.ToArray() }
}

function Get-ZustandsDiff($Vor, $Nach) {
    # Pfade, deren Statuszeile sich verändert hat (neu, weg oder anders)
    $a = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Vor.Status), [StringComparer]::Ordinal)
    $b = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Nach.Status), [StringComparer]::Ordinal)
    $pfade = [System.Collections.Generic.List[string]]::new()
    foreach ($z in @(@($Vor.Status) + @($Nach.Status))) {
        if ($a.Contains($z) -and $b.Contains($z)) { continue }
        $p = if ($z.Length -gt 3) { $z.Substring(3) } else { $z }
        if (-not $pfade.Contains($p)) { $pfade.Add($p) }
    }
    return $pfade.ToArray()
}

function Invoke-FastForward($Ctx, [string]$Sha) {
    $hb = $Ctx.Cfg.hauptbranch
    $sperre = Lock-Datei (Join-Path $Ctx.LockDir 'main.lock') 120 'Hauptcheckout-Sperre' ''
    try {
        Assert-HauptAufHauptbranch $Ctx
        for ($i = 0; ; $i++) {
            # nur HEAD und die Pfade, die der ff schreiben würde, zählen beim Teilzustands-Vergleich
            $d = Invoke-GitOk $Ctx.Main @('diff', '--name-only', '-z', '--no-renames', '--ignore-submodules=none', '--no-ext-diff',
                '--no-relative', 'HEAD', $Sha)
            $pfade = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($p in $d.Out.Split([char]0)) { if ($p) { [void]$pfade.Add($p) } }
            $vor = Get-HauptZustand $Ctx $pfade
            $r = Invoke-Git $Ctx.Main @('merge', '--ff-only', '--no-autostash', '--no-overwrite-ignore', $Sha)
            if ($r.Code -eq 0) {
                Write-Host "ff von $hb auf $(Kurz $Sha)"
                return 'ok'
            }
            $text = $r.Out + "`n" + $r.Err
            # bei diesen Meldungen bricht git vor dem Schreiben ab
            if ($text -match 'Not possible to fast-forward') { return 'bewegt' }
            if ($text -match 'would be overwritten') {
                Write-Host 'ff-Merge verweigert – im Hauptcheckout würden Dateien überschrieben:'
                foreach ($z in ($text -split "`n")) { if ($z -match '^\t(.+?)\r?$') { Write-Host "  $($Matches[1])" } }
                Stop-Wt 12 'BLOCKIERT' 'ff-Merge: uncommittete oder ungetrackte Dateien im Hauptcheckout würden überschrieben (would be overwritten)'
            }
            # sonst gescheitert: hat der Merge schon geschrieben (HEAD oder ein ff-Pfad verändert), ist das ein Teilzustand
            $nach = Get-HauptZustand $Ctx $pfade
            $veraendert = @(Get-ZustandsDiff $vor $nach)
            if ($vor.Head -ne $nach.Head -or $veraendert.Count) {
                Write-GitZeilen $r
                if ($vor.Head -ne $nach.Head) { Write-Host "HEAD im Hauptcheckout vorher $(Kurz $vor.Head), nachher $(Kurz $nach.Head)" }
                if ($veraendert.Count) {
                    Write-Host 'veränderte Pfade im Hauptcheckout:'
                    $veraendert | Select-Object -First 30 | ForEach-Object { Write-Host "  $_" }
                }
                $liste = (@($veraendert | Select-Object -First 10) -join ', ')
                Stop-Wt 13 'TEILZUSTAND' ("ff-Merge gescheitert, Hauptcheckout verändert ({0} Pfade: {1}) – sofort stoppen, im Hauptcheckout nichts committen, Mensch" -f $veraendert.Count, $liste)
            }
            if ($text -match 'update_ref failed|cannot lock ref') {
                Write-GitZeilen $r
                Show-HauptStatus $Ctx
                Stop-Wt 13 'TEILZUSTAND' 'ff-Merge nach dem Schreiben von Index/Arbeitsbaum gescheitert – sofort stoppen, im Hauptcheckout nichts committen, Mensch'
            }
            if ($text -match 'index\.lock') {
                if ($i -lt 3) { Write-Host 'index.lock im Hauptcheckout belegt – neuer Versuch in 3 s'; Start-Sleep -Seconds 3; continue }
                Stop-Wt 12 'BLOCKIERT' 'index.lock im Hauptcheckout dauerhaft belegt'
            }
            Write-GitZeilen $r
            Stop-Wt 12 'BLOCKIERT' "ff-Merge gescheitert: $(Get-GitKurz $r)"
        }
    } finally {
        $sperre.Dispose()
    }
}

# ---------------------------------------------------------------- Befehle

function Sync-Worktree($Ctx, [string]$K, [string]$WtDir) {
    $hb = $Ctx.Cfg.hauptbranch
    Assert-KeineOperation $WtDir "Worktree $K"
    Assert-Sauber $WtDir "Worktree $K" $Ctx.Cfg.gateAblage
    $branch = Get-AktuellerBranch $WtDir
    if (-not $branch) { Stop-Wt 12 'BLOCKIERT' "Worktree $K hat keinen Branch (detached HEAD)" }
    if ($branch -ceq $hb) { Stop-Wt 12 'BLOCKIERT' "Worktree $K steht auf $hb statt auf einem Issue-Branch" }
    if ((Get-Anzahl $WtDir "refs/heads/$hb..HEAD") -eq 0) {
        if ((Get-Anzahl $WtDir "HEAD..refs/heads/$hb") -eq 0) {
            Write-Host "$branch ist auf dem Stand von $hb"
            return $branch
        }
        $r = Invoke-Git $WtDir @('merge', '--ff-only', '--no-autostash', "refs/heads/$hb")
        if ($r.Code -ne 0) {
            Write-GitZeilen $r
            Stop-Wt 12 'BLOCKIERT' "ff von $branch auf $hb nicht möglich: $(Get-GitKurz $r)"
        }
        Write-Host "$branch per ff auf $hb gebracht"
        return $branch
    }
    [void](Invoke-RebaseSchritt $WtDir $hb $branch)
    return $branch
}

function Invoke-CmdSync($Ctx) {
    $k = Resolve-Key $Ctx
    Assert-KonfigUnveraendert $Ctx
    $wtDir = Get-WtDir $Ctx $k
    if ($null -eq (Find-Worktree $Ctx $wtDir) -or -not (Test-Path -LiteralPath $wtDir -PathType Container)) {
        Assert-KeineProbeReste $wtDir
        Stop-Wt 12 'BLOCKIERT' "kein Worktree für $k unter $wtDir – zuerst wt start"
    }
    # wie start: eine uncommittete Neufreigabe im Hauptcheckout käme sonst nicht im Worktree an
    Test-IssueOrdnerSauber $Ctx $k
    $branch = Sync-Worktree $Ctx $k $wtDir
    $head = First (Invoke-GitOk $wtDir @('rev-parse', 'HEAD')).Lines
    Stop-Wt 0 'OK' ("{0} ({1}) aktuell auf {2}, HEAD {3}" -f $k, $branch, $Ctx.Cfg.hauptbranch, (Kurz $head))
}

function Test-IssueOrdnerSauber($Ctx, [string]$K) {
    $offen = [System.Collections.Generic.List[string]]::new()
    foreach ($ordner in $Ctx.Cfg.issueOrdner) {
        $basis = Join-Path $Ctx.Main $ordner.TrimEnd('/')
        if (-not (Test-Path -LiteralPath $basis -PathType Container)) { continue }
        foreach ($e in Get-ChildItem -LiteralPath $basis -Force) {
            $n = $e.Name
            if (-not $n.StartsWith($K, [StringComparison]::OrdinalIgnoreCase)) { continue }
            if ($n.Length -gt $K.Length -and [char]::IsDigit($n[$K.Length])) { continue }
            $rel = $ordner.TrimEnd('/') + '/' + $n
            $r = Invoke-GitOk $Ctx.Main @('status', '--porcelain', '-uall', '--ignore-submodules=none', '--', $rel)
            foreach ($z in $r.Lines) { $offen.Add($z) }
        }
    }
    if ($offen.Count) {
        Write-Host 'Issue-Ordner im Hauptcheckout hat uncommittete Änderungen (zuerst per wt commit festschreiben):'
        $offen | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
        Stop-Wt 12 'BLOCKIERT' "Issue-Ordner von $K im Hauptcheckout nicht sauber ($($offen.Count) Einträge)"
    }
}

function Invoke-CmdStart($Ctx) {
    $cfg = $Ctx.Cfg
    $hb = $cfg.hauptbranch
    $k = Resolve-Key $Ctx
    if ($Slug -and ($Slug -cnotmatch $script:SlugMuster -or $Slug.Length -gt 40)) {
        Stop-Wt 1 'FEHLER' "ungültiger Slug '$Slug' (Kleinbuchstaben, Ziffern, Bindestriche; höchstens 40 Zeichen)"
    }
    Assert-KonfigUnveraendert $Ctx
    Assert-HauptAufHauptbranch $Ctx
    $wtDir = Get-WtDir $Ctx $k
    $wt = Find-Worktree $Ctx $wtDir
    Assert-KeineProbeReste $wtDir
    if (Test-Path -LiteralPath $wtDir) {
        if ($null -eq $wt) { Stop-Wt 12 'BLOCKIERT' "Ordner $wtDir existiert, ist aber kein registrierter Worktree" }
        Write-Host "Worktree vorhanden: $wtDir – wird wiederverwendet"
        Test-IssueOrdnerSauber $Ctx $k
        # vor dem Sync: endet er mit 10, braucht die Session den Pfad trotzdem
        $branchVor = Get-AktuellerBranch $wtDir
        Write-Host "WORKTREE=$wtDir"
        if ($branchVor) { Write-Host "BRANCH=$branchVor" }
        Copy-WorktreeInclude $Ctx $wtDir
        [void](Initialize-GateLogDir $Ctx $wtDir)
        $branch = Sync-Worktree $Ctx $k $wtDir
        if ($Slug -and -not [string]::Equals($branch, "$k-$Slug", [StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "Hinweis: vorhandener Branch $branch wird verwendet; -Slug ignoriert"
        }
        Stop-Wt 0 'OK' "Worktree $wtDir, Branch $branch (wiederverwendet)"
    }
    if ($null -ne $wt) {
        Stop-Wt 12 'BLOCKIERT' "Worktree $wtDir ist registriert, der Ordner fehlt – 'git worktree prune' durch den Menschen"
    }
    $branches = @(Find-KeyBranches $Ctx $k)
    if ($branches.Count -gt 1) {
        Stop-Wt 12 'BLOCKIERT' ("mehrere Branches für {0}: {1}" -f $k, ($branches -join ', '))
    }
    if ($branches.Count -eq 0 -and -not $Slug) { Stop-Wt 1 'FEHLER' "kein Branch für $k vorhanden – -Slug erforderlich" }
    Test-IssueOrdnerSauber $Ctx $k
    $angehaengt = $branches.Count -eq 1
    if ($angehaengt) {
        $branch = $branches[0]
        if ($Slug -and -not [string]::Equals($branch, "$k-$Slug", [StringComparison]::OrdinalIgnoreCase)) {
            Write-Host "Hinweis: vorhandener Branch $branch wird verwendet; -Slug ignoriert"
        }
        Add-Ignoriert $Ctx $cfg.worktreeRoot
        $r = Invoke-Git $Ctx.Main @('worktree', 'add', $wtDir, $branch)
    } else {
        $branch = "$k-$Slug"
        Add-Ignoriert $Ctx $cfg.worktreeRoot
        $r = Invoke-Git $Ctx.Main @('worktree', 'add', '-b', $branch, $wtDir, "refs/heads/$hb")
    }
    if ($r.Code -ne 0) {
        Write-GitZeilen $r
        Stop-Wt 12 'BLOCKIERT' "git worktree add fehlgeschlagen: $(Get-GitKurz $r)"
    }
    Write-Host "Worktree angelegt: $wtDir (Branch $branch)"
    Write-Host "WORKTREE=$wtDir"
    Write-Host "BRANCH=$branch"
    Copy-WorktreeInclude $Ctx $wtDir
    # Gate-Ablage immer anlegen und ignorieren: die erste Sicherung einer Review-Session kommt vor jedem Gate
    $logDir = Initialize-GateLogDir $Ctx $wtDir
    if ($cfg.setup) { Invoke-Setup $Ctx $wtDir $logDir }
    # angehängter Branch: auf den aktuellen Stand bringen (Konflikt → Rebase abgebrochen, 10)
    if ($angehaengt) { $branch = Sync-Worktree $Ctx $k $wtDir }
    Stop-Wt 0 'OK' "Worktree $wtDir, Branch $branch"
}

function Assert-WorktreeUnveraendert($Ctx, [string]$WtDir, [string]$K, [string]$Branch) {
    # nach Erhalt der Integrationssperre und zu Beginn jedes Versuchs: Gate und Nachweis gelten dem HEAD-Tree
    $grund = ''
    if (-not (Test-Path -LiteralPath $WtDir -PathType Container)) {
        $grund = 'Ordner fehlt'
    } else {
        $ops = @(Get-OffeneOperationen $WtDir)
        if ($ops.Count) {
            $grund = "offene Operation $($ops -join '/')"
        } else {
            $b = Get-AktuellerBranch $WtDir
            if ($b -cne $Branch) {
                $grund = if ($b) { "Branch jetzt $b statt $Branch" } else { 'detached HEAD' }
            } else {
                $z = @(Get-StatusZeilen $WtDir $Ctx.Cfg.gateAblage)
                if ($z.Count) {
                    Write-Host "Worktree $K hat uncommittete Änderungen:"
                    $z | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
                    $grund = "$($z.Count) uncommittete Einträge"
                }
            }
        }
    }
    if ($grund) { Stop-Wt 12 'BLOCKIERT' "Worktree während der Wartezeit verändert (${K}: $grund) – kein Gate, keine Integration" }
}

function Get-HinzugefuegtePfade([string]$Dir, [string]$Hb) {
    # Pfade, die der Branch seit der Basis hinzufügt oder unter neuem Namen führt (A, R)
    $teile = (Invoke-GitOk $Dir @('diff', '--name-status', '-z', '-M', '--diff-filter=AR', '--no-ext-diff', '--no-relative',
            "refs/heads/$Hb...HEAD")).Out.Split([char]0)
    $i = 0
    while ($i -lt $teile.Count) {
        $st = $teile[$i]
        if (-not $st) { $i++; continue }
        if ($st.StartsWith('R') -or $st.StartsWith('C')) {
            if ($i + 2 -lt $teile.Count) { $teile[$i + 2] }
            $i += 3
        } else {
            if ($i + 1 -lt $teile.Count) { $teile[$i + 1] }
            $i += 2
        }
    }
}

function Invoke-CmdIntegrate($Ctx) {
    $cfg = $Ctx.Cfg
    $hb = $cfg.hauptbranch
    $k = Resolve-Key $Ctx
    Assert-KonfigUnveraendert $Ctx
    if ($null -eq $cfg.gate) {
        Stop-Wt 12 'BLOCKIERT' "Projektwert 'gate' fehlt in .ai-sdlc/arbeitsbaeume.json (`"`" heißt bewusst keine Gate-Kette)"
    }
    Assert-HauptAufHauptbranch $Ctx
    $wtDir = Get-WtDir $Ctx $k
    if ($null -eq (Find-Worktree $Ctx $wtDir) -or -not (Test-Path -LiteralPath $wtDir -PathType Container)) {
        Stop-Wt 12 'BLOCKIERT' "kein Worktree für $k unter $wtDir – zuerst wt start"
    }
    Assert-KeineOperation $wtDir "Worktree $k"
    Assert-Sauber $wtDir "Worktree $k" $cfg.gateAblage
    $branch = Get-AktuellerBranch $wtDir
    if (-not $branch) { Stop-Wt 12 'BLOCKIERT' "Worktree $k hat keinen Branch (detached HEAD)" }
    if ($branch -ceq $hb) { Stop-Wt 12 'BLOCKIERT' "Worktree $k steht auf $hb statt auf einem Issue-Branch" }
    if ((Get-Anzahl $wtDir "refs/heads/$hb..HEAD") -eq 0) {
        Stop-Wt 14 'NICHTS' "Branch $branch hat keine Commits außerhalb von $hb"
    }
    Assert-KeineMergeCommits $wtDir $hb "refs/heads/$branch" $branch

    $inhaber = Join-Path $Ctx.LockDir 'integration.owner'
    $sperre = Lock-Datei (Join-Path $Ctx.LockDir 'integration.lock') ($cfg.sperreWartenMinuten * 60) 'Integrationssperre' $inhaber
    $rebased = $false
    $laufBasis = ''
    $laufTip = ''
    try {
        Assert-KeinVerwaistesGate $inhaber
        Write-Inhaber $inhaber $k
        $n = 1
        for ($v = 1; $v -le $n; $v++) {
            # das Warten auf die Sperre kann Stunden dauern: Projektwerte neu aus HEAD, je Versuch
            Update-KontextKonfig $Ctx
            $cfg = $Ctx.Cfg
            $hb = $cfg.hauptbranch
            $n = $cfg.integrationsVersuche
            if ($null -eq $cfg.gate) {
                Stop-Wt 12 'BLOCKIERT' "Projektwert 'gate' fehlt inzwischen in .ai-sdlc/arbeitsbaeume.json – keine Integration"
            }
            Assert-HauptAufHauptbranch $Ctx
            Assert-WorktreeUnveraendert $Ctx $wtDir $k $branch
            Assert-KeineMergeCommits $wtDir $hb "refs/heads/$branch" $branch
            if ($v -eq 1) {
                $laufBasis = First (Invoke-GitOk $wtDir @('merge-base', "refs/heads/$hb", 'HEAD')).Lines
                $laufTip = First (Invoke-GitOk $wtDir @('rev-parse', 'HEAD')).Lines
            }
            Write-Host "Versuch $v/${n}: Rebase von $branch auf $hb"
            try {
                if (Invoke-RebaseSchritt $wtDir $hb $branch) { $rebased = $true }
            } catch [WtExit] {
                if ($_.Exception.Code -eq 10 -and $rebased) {
                    Write-Host "Hinweis: $branch wurde in diesem Lauf bereits rebased (Stand vor dem Lauf: Basis $(Kurz $laufBasis), Tip $(Kurz $laufTip))"
                }
                throw
            }
            if ((Get-Anzahl $wtDir "refs/heads/$hb..HEAD") -eq 0) {
                Stop-Wt 14 'NICHTS' "nach dem Rebase hat $branch keine eigenen Commits mehr"
            }
            $sha = First (Invoke-GitOk $wtDir @('rev-parse', 'HEAD')).Lines

            $pfade = @((Invoke-GitOk $wtDir @('diff', '--name-only', '--no-renames', '--ignore-submodules=none', '--no-ext-diff',
                        '--no-relative', "refs/heads/$hb...HEAD")).Lines)
            $verstoesse = @(Get-NurAufMainVerstoesse $cfg $pfade)
            if ($verstoesse.Count) {
                Write-Host 'Dateien aus nurAufMain im Branch:'
                $verstoesse | ForEach-Object { Write-Host "  $_" }
                Stop-Wt 12 'BLOCKIERT' ("Branch ändert nurAufMain-Dateien: {0}" -f ($verstoesse -join ', '))
            }

            # nur Dubletten mit einem Namen, den der Branch hinzufügt oder umbenennt; vorhandene sind Altlast (WARNUNG)
            $hinzu = @(Get-HinzugefuegtePfade $wtDir $hb)
            $doppelt = [System.Collections.Generic.List[string]]::new()
            $altlast = [System.Collections.Generic.List[string]]::new()
            foreach ($np in $cfg.nummernPruefung) {
                $praefix = "$($np.ordner)/"
                $namen = @(Split-Nul (Invoke-GitOk $wtDir @('ls-tree', '-z', '--name-only', 'HEAD', '--', $praefix)).Out |
                        ForEach-Object { @($_ -split '/')[-1] })
                $neu = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                foreach ($p in $hinzu) {
                    if ($p.StartsWith($praefix, [StringComparison]::OrdinalIgnoreCase)) { [void]$neu.Add(@($p.Substring($praefix.Length) -split '/')[0]) }
                }
                $blockiert = @(Get-Dubletten $np $namen $neu)
                foreach ($d in $blockiert) { $doppelt.Add($d) }
                foreach ($d in @(Get-Dubletten $np $namen $null)) { if ($blockiert -notcontains $d) { $altlast.Add($d) } }
            }
            if ($altlast.Count) {
                Write-WarnungEinmal ("WARNUNG: doppelte Nummer schon auf {0} (Altlast, blockiert nicht): {1}" -f $hb, ($altlast -join '; '))
            }
            if ($doppelt.Count) {
                Write-Host 'doppelte Nummern:'
                $doppelt | ForEach-Object { Write-Host "  $_" }
                Stop-Wt 12 'BLOCKIERT' ("doppelte Nummer: {0}" -f ($doppelt -join '; '))
            }

            Invoke-IntegrationsGate $Ctx $wtDir $branch $sha $inhaber

            $ergebnis = Invoke-FastForward $Ctx $sha
            if ($ergebnis -eq 'ok') {
                $anc = Invoke-Git $Ctx.Main @('merge-base', '--is-ancestor', $sha, "refs/heads/$hb")
                if ($anc.Code -ne 0) {
                    Show-HauptStatus $Ctx
                    Stop-Wt 13 'TEILZUSTAND' "ff gemeldet, aber $(Kurz $sha) ist nicht in $hb enthalten – im Hauptcheckout nichts committen, Mensch"
                }
                Stop-Wt 0 'OK' ("integriert: {0} ({1}) {2} in {3}" -f $k, $branch, (Kurz $sha), $hb)
            }
            Write-Host "$hb hat sich bewegt (kein ff möglich) – neuer Versuch"
        }
        Stop-Wt 12 'BLOCKIERT' "nach $n Versuchen nicht integriert – $hb bewegt sich laufend"
    } catch [WtExit] {
        $x = $_.Exception
        if ($rebased -and $x.Code -ne 0 -and $x.Code -ne 10) {
            # der Branch ist umgeschrieben: alte Sicherungen haben keinen Vorfahren-HEAD mehr
            Write-Host 'Branch wurde rebased – Stand vor diesem Lauf (vor einem Fix neue Sicherung vom aktuellen HEAD):'
            Write-Host "ALTE_BASIS=$laufBasis"
            Write-Host "ALTER_TIP=$laufTip"
            Stop-Wt $x.Code $x.Status ("{0}; Branch wurde rebased" -f $x.Message)
        }
        throw
    } finally {
        Unlock-Integration $sperre
    }
}

function Get-DateiListe([string]$Wurzel) {
    $liste = [System.Collections.Generic.List[string]]::new()
    foreach ($a in @($Dateien)) {
        if ($null -eq $a -or $a.Trim() -eq '') { continue }
        if ($a.StartsWith('-')) { Stop-Wt 1 'FEHLER' "unbekannter Parameter: $a" }
        $p = $a.Trim().Replace('\', '/')
        while ($p.StartsWith('./')) { $p = $p.Substring(2) }
        if ($p -match '^[A-Za-z]:' -or $p.StartsWith('/')) { Stop-Wt 1 'FEHLER' "Pfad muss relativ zur Wurzel des Checkouts sein: $a" }
        $teile = @($p -split '/')
        if ($p.EndsWith('/') -or $teile -contains '..' -or $teile -contains '.' -or $teile -contains '') {
            Stop-Wt 1 'FEHLER' "ungültiger Dateipfad: $a"
        }
        if (Test-Path -LiteralPath (Join-Path $Wurzel $p) -PathType Container) { Stop-Wt 1 'FEHLER' "Verzeichnis statt Datei: $a" }
        $doppelt = $false
        foreach ($x in $liste) { if ([string]::Equals($x, $p, [StringComparison]::OrdinalIgnoreCase)) { $doppelt = $true } }
        if (-not $doppelt) { $liste.Add($p) }
    }
    if ($liste.Count -eq 0) { Stop-Wt 1 'FEHLER' 'commit braucht mindestens eine Datei' }
    return $liste.ToArray()
}

function Split-Nul([string]$Text) { return @($Text.Split([char]0) | Where-Object { $_ -ne '' }) }

function Get-PfadBekannt([string]$Wurzel, [string[]]$Liste) {
    # bekannt ist ein Pfad, der im Index oder in HEAD steht (git rm, git mv); neu sind nur ganz unbekannte.
    # Bricht mit 1 ab, wenn ein Pfad weder vorhanden noch bekannt ist.
    $imIndex = @(Split-Nul (Invoke-GitOk $Wurzel (@('ls-files', '-z', '--') + $Liste)).Out)
    $imHead = @()
    $lt = Invoke-Git $Wurzel (@('ls-tree', '-r', '-z', '--name-only', 'HEAD', '--') + $Liste)
    if ($lt.Code -eq 0) { $imHead = @(Split-Nul $lt.Out) }
    $neu = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $Liste) {
        $vorhanden = Test-Path -LiteralPath (Join-Path $Wurzel $f) -PathType Leaf
        $bekannt = ($imIndex -contains $f) -or ($imHead -contains $f)
        if (-not $vorhanden -and -not $bekannt) { Stop-Wt 1 'FEHLER' "Datei weder vorhanden noch versioniert (Index, HEAD): $f" }
        if ($vorhanden -and -not $bekannt) { $neu.Add($f) }
    }
    return [pscustomobject]@{ ImHead = [string[]]$imHead; Neu = [string[]]$neu.ToArray() }
}

function Assert-KeineHalbeUmbenennung([string]$Wurzel, [string[]]$Liste, [string[]]$ImHead) {
    # git mv mit nur dem neuen Pfad: committet würde eine Kopie, die gestagte Löschung bliebe im Index liegen
    $neuGenannt = @($Liste | Where-Object { $ImHead -notcontains $_ })
    if (-not $neuGenannt.Count) { return }
    $d = Invoke-Git $Wurzel @('diff', '--cached', '--raw', '-z', '--no-abbrev', '--no-renames', '--diff-filter=D', 'HEAD')
    if ($d.Code -ne 0) { return }
    # Blob je gestagt gelöschtem, nicht genanntem Pfad
    $alt = @{}
    $teile = $d.Out.Split([char]0)
    for ($i = 0; $i + 1 -lt $teile.Count; $i += 2) {
        if ($teile[$i] -match '^:\d+ \d+ ([0-9a-f]+) [0-9a-f]+ D') {
            if ($Liste -notcontains $teile[$i + 1]) { $alt[$Matches[1]] = $teile[$i + 1] }
        }
    }
    if (-not $alt.Count) { return }
    # leerer Inhalt passte auf jede leere Datei
    $leer = First (Invoke-Git $Wurzel @('hash-object', '--stdin')).Lines
    $imIndex = @{}
    foreach ($z in Split-Nul (Invoke-Git $Wurzel (@('ls-files', '-s', '-z', '--') + $neuGenannt)).Out) {
        if ($z -match '^\d{6} ([0-9a-f]+) 0\t(.+)$') { $imIndex[$Matches[2]] = $Matches[1] }
    }
    $treffer = [System.Collections.Generic.List[string]]::new()
    foreach ($n in $neuGenannt) {
        $blobs = [System.Collections.Generic.List[string]]::new()
        if ($imIndex.ContainsKey($n)) { $blobs.Add($imIndex[$n]) }
        if (Test-Path -LiteralPath (Join-Path $Wurzel $n) -PathType Leaf) {
            $h = Invoke-Git $Wurzel @('hash-object', '--', $n)
            if ($h.Code -eq 0) { $blobs.Add((First $h.Lines)) }
        }
        foreach ($b in $blobs) {
            if ($b -and $b -ne $leer -and $alt.ContainsKey($b)) { $treffer.Add("$($alt[$b]) -> $n"); break }
        }
    }
    if ($treffer.Count) {
        Write-Host 'gestagte Löschung mit dem Inhalt einer genannten neuen Datei (git mv mit nur neuem Pfad?):'
        $treffer | ForEach-Object { Write-Host "  $_" }
        Stop-Wt 12 'BLOCKIERT' ("alten Pfad mitnennen: {0} – nichts committet" -f ($treffer -join ', '))
    }
}

function Get-StatusPfade([string]$Wurzel, [string[]]$Liste) {
    # Pfade aus $Liste mit einem Statuseintrag (Index oder Arbeitskopie weicht von HEAD ab, ungetrackt)
    $teile = (Invoke-GitOk $Wurzel (@('status', '--porcelain', '-z', '--ignore-submodules=none', '--') + $Liste)).Out.Split([char]0)
    for ($i = 0; $i -lt $teile.Count; $i++) {
        $e = $teile[$i]
        if ($e.Length -lt 4) { continue }
        $e.Substring(3)
        if ($e.Substring(0, 2).Contains('R') -or $e.Substring(0, 2).Contains('C')) { $i++ }
    }
}

function Invoke-PfadCommit([string]$Wurzel, [string[]]$Liste) {
    $pb = Get-PfadBekannt $Wurzel $Liste
    Assert-KeineHalbeUmbenennung $Wurzel $Liste $pb.ImHead
    $neu = $pb.Neu
    if ($neu.Count) {
        $r = Invoke-GitMitWiederholung $Wurzel (@('add', '-N', '--') + $neu) 'git add -N'
        if ($r.Code -ne 0) {
            Write-GitZeilen $r
            Stop-Wt 12 'BLOCKIERT' "git add -N fehlgeschlagen: $(Get-GitKurz $r)"
        }
    }
    $r = Invoke-GitMitWiederholung $Wurzel (@('commit', '-m', $Nachricht, '--') + $Liste) 'git commit'
    if ($r.Code -ne 0) {
        # nur die eben per add -N eingetragenen Pfade wieder austragen
        if ($neu.Count) { [void](Invoke-Git $Wurzel (@('reset', '-q', '--') + $neu)) }
        $text = $r.Out + "`n" + $r.Err
        if ($text -match 'nothing added|no changes added|nothing to commit') {
            Stop-Wt 14 'NICHTS' 'keine Änderungen an den genannten Dateien'
        }
        Write-GitZeilen $r
        Stop-Wt 12 'BLOCKIERT' "git commit fehlgeschlagen: $(Get-GitKurz $r)"
    }
    $sha = First (Invoke-GitOk $Wurzel @('rev-parse', 'HEAD')).Lines
    $gezeigt = @(Split-Nul (Invoke-GitOk $Wurzel @('show', '--name-only', '-z', '--no-renames', '--format=', '--ignore-submodules=none',
                '--no-ext-diff', 'HEAD')).Out)
    $fremd = @($gezeigt | Where-Object { $Liste -notcontains $_ })
    if ($fremd.Count) {
        Write-Host 'Commit enthält nicht genannte Dateien:'
        $fremd | ForEach-Object { Write-Host "  $_" }
        Stop-Wt 12 'BLOCKIERT' ("Commit {0} angelegt, enthält aber nicht genannte Dateien ({1}) – prüfen, Mensch" -f (Kurz $sha), ($fremd -join ', '))
    }
    # weicht eine genannte Datei danach ab, hat ein Hook sie verändert (z. B. Formatter mit git add): Index hält
    # sonst den alten Stand (MM), HEAD und Arbeitskopie den neuen
    $offen = @(Get-StatusPfade $Wurzel $Liste)
    if ($offen.Count) {
        $rs = Invoke-GitMitWiederholung $Wurzel (@('reset', '-q', 'HEAD', '--') + $offen) 'git reset (vom Hook veränderte Pfade)'
        $index = if ($rs.Code -eq 0) { 'Indexeinträge auf HEAD gesetzt' } else { "Indexeinträge nicht angeglichen ($(Get-GitKurz $rs))" }
        Write-Host 'Genannte Dateien nach dem Commit verändert:'
        $offen | ForEach-Object { Write-Host "  $_" }
        $rest = @(Get-StatusPfade $Wurzel $offen)
        $wk = if ($rest.Count) { "Arbeitskopie weicht ab, uncommittet: $($rest -join ', ')" } else { 'Commit enthält den Hook-Stand, Arbeitskopie gleich' }
        Stop-Wt 12 'BLOCKIERT' ("Commit {0} angelegt, Hook hat Dateien verändert: {1} – {2}; {3}; Commit prüfen" -f (Kurz $sha), ($offen -join ', '), $index, $wk)
    }
    return $sha
}

function Assert-NummernHauptCommit($Ctx, [string[]]$Liste, $Vorhanden = $null) {
    # Hauptcheckout: HEAD-Tree plus die genannten Dateien darf keine neue doppelte Nummer enthalten. Neu ist nur
    # ein Name, der in HEAD noch nicht steht; schon vorhandene Dubletten (Altlast) nur als WARNUNG.
    # $Vorhanden: Pfad → vorhanden (gegateter Stand bei commit -Gate), sonst zählt die Arbeitskopie
    $doppelt = [System.Collections.Generic.List[string]]::new()
    $altlast = [System.Collections.Generic.List[string]]::new()
    foreach ($np in $Ctx.Cfg.nummernPruefung) {
        $praefix = "$($np.ordner)/"
        $betroffen = @($Liste | Where-Object { $_.StartsWith($praefix, [StringComparison]::OrdinalIgnoreCase) })
        if (-not $betroffen.Count) { continue }
        $imHead = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $namen = [System.Collections.Generic.List[string]]::new()
        $lt = Invoke-Git $Ctx.Main @('ls-tree', '-z', '--name-only', 'HEAD', '--', $praefix)
        if ($lt.Code -eq 0) {
            foreach ($n in Split-Nul $lt.Out) {
                $blatt = @($n -split '/')[-1]
                $namen.Add($blatt)
                [void]$imHead.Add($blatt)
            }
        }
        $neu = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($f in $betroffen) {
            $rest = $f.Substring($praefix.Length)
            $kind = @($rest -split '/')[0]
            $da = if ($null -ne $Vorhanden -and $Vorhanden.Contains($f)) { [bool]$Vorhanden[$f] }
                  else { Test-Path -LiteralPath (Join-Path $Ctx.Main $f) -PathType Leaf }
            if ($da) {
                if (-not $namen.Contains($kind)) { $namen.Add($kind) }
                if (-not $imHead.Contains($kind)) { [void]$neu.Add($kind) }
            } elseif (-not $rest.Contains('/')) {
                [void]$namen.Remove($kind)
            }
        }
        $blockiert = @(Get-Dubletten $np $namen.ToArray() $neu)
        foreach ($d in $blockiert) { $doppelt.Add($d) }
        foreach ($d in @(Get-Dubletten $np $namen.ToArray() $null)) { if ($blockiert -notcontains $d) { $altlast.Add($d) } }
    }
    if ($altlast.Count) {
        Write-WarnungEinmal ("WARNUNG: doppelte Nummer schon in HEAD (Altlast, blockiert nicht): {0}" -f ($altlast -join '; '))
    }
    if ($doppelt.Count) {
        Write-Host 'doppelte Nummern (HEAD plus genannte Dateien):'
        $doppelt | ForEach-Object { Write-Host "  $_" }
        Stop-Wt 12 'BLOCKIERT' ("doppelte Nummer: {0}" -f ($doppelt -join '; '))
    }
}

function Invoke-HauptCommit($Ctx, [string[]]$Liste) {
    $sperre = Lock-Datei (Join-Path $Ctx.LockDir 'main.lock') 120 'Hauptcheckout-Sperre' ''
    try {
        Assert-HauptAufHauptbranch $Ctx
        Assert-NummernHauptCommit $Ctx $Liste
        return (Invoke-PfadCommit $Ctx.Main $Liste)
    } finally {
        $sperre.Dispose()
    }
}

function Remove-WorktreeLinks([string]$Dir) {
    # Vor jedem Löschen eines Worktrees: Junctions und Symlinks darin aufzählen, ohne ihnen zu folgen, und nur
    # die Links selbst entfernen – git worktree remove folgt unter Windows Junctions und leerte deren Ziel
    # (z. B. node_modules per npm file: oder ein setup, das Ordner des Hauptcheckouts teilt).
    # Liefert $null oder den Grund, warum nichts weiter gelöscht werden darf.
    if (-not [IO.Directory]::Exists($Dir)) { return $null }
    if ([IO.File]::GetAttributes($Dir) -band [IO.FileAttributes]::ReparsePoint) {
        return "$Dir ist selbst eine Junction bzw. ein Symlink"
    }
    $fehler = $null
    $links = @(Get-ChildItem -LiteralPath $Dir -Recurse -Force -Attributes ReparsePoint -ErrorAction SilentlyContinue -ErrorVariable fehler)
    if (@($fehler).Count) {
        Write-Host "Worktree $Dir nicht vollständig lesbar – Links lassen sich nicht sicher ausschließen:"
        @($fehler) | Select-Object -First 20 | ForEach-Object { Write-Host "  $($_.Exception.Message)" }
        return "Worktree nicht vollständig lesbar ($(@($fehler).Count) Fehler)"
    }
    if (-not $links.Count) { return $null }
    # von git verwaltete Symlinks (Modus 120000) entfernt git selbst, ohne ihnen zu folgen; fehlten sie, sähe
    # git gelöschte Dateien und verweigerte das Entfernen
    $versioniert = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    if (@($links | Where-Object { $_.LinkType -eq 'SymbolicLink' }).Count) {
        $ls = Invoke-Git $Dir @('ls-files', '-s', '-z')
        if ($ls.Code -eq 0) {
            foreach ($z in Split-Nul $ls.Out) { if ($z -match '^120000 [0-9a-f]+ 0\t(.+)$') { [void]$versioniert.Add($Matches[1]) } }
        }
    }
    $nicht = [System.Collections.Generic.List[string]]::new()
    foreach ($l in $links) {
        $rel = [IO.Path]::GetRelativePath($Dir, $l.FullName).Replace('\', '/')
        if ($l.LinkType -eq 'SymbolicLink' -and $versioniert.Contains($rel)) { continue }
        $ziel = $null
        try { $ziel = $l.LinkTarget } catch { $ziel = $null }
        if (-not $ziel) { $ziel = '(Ziel unbekannt)' }
        try {
            if ($l.Attributes -band [IO.FileAttributes]::Directory) { [IO.Directory]::Delete($l.FullName, $false) }
            else { [IO.File]::Delete($l.FullName) }
            Write-Host "Link entfernt (Ziel unangetastet): $rel -> $ziel"
        } catch {
            $grund = if ($null -ne $_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
            Write-Host "Link nicht entfernbar: $rel -> $ziel ($grund)"
            $nicht.Add($rel)
        }
    }
    if ($nicht.Count) {
        return ("{0} Link(s) nicht entfernbar: {1}" -f $nicht.Count, (@($nicht | Select-Object -First 5) -join ', '))
    }
    return $null
}

function Remove-GateWorktree($Ctx, [string]$Dir) {
    # baut einen temporären Gate-Worktree ab (erst die Links, dann worktree remove); wirft nie, liefert $null oder
    # den Grund, warum er stehen bleibt
    try {
        $grund = Remove-WorktreeLinks $Dir
        if ($grund) {
            Write-Host "temporärer Gate-Worktree $Dir bleibt stehen (nichts gelöscht): $grund"
            return $grund
        }
        $r = Invoke-Git $Ctx.Main @('worktree', 'remove', '--force', $Dir)
        if ($r.Code -ne 0) { Write-Host "WARNUNG: temporärer Worktree $Dir nicht entfernt (Rest räumt der nächste Lauf): $(Get-GitKurz $r)" }
        return $null
    } catch {
        Write-Host "temporärer Gate-Worktree ${Dir}: Abbau gescheitert ($($_.Exception.Message))"
        return "Abbau gescheitert: $($_.Exception.Message)"
    }
}

function Remove-VerwaisteGateWorktrees($Ctx) {
    foreach ($w in @(Get-Worktrees $Ctx.Main)) {
        $eltern = Norm (Split-Path -Parent $w.Path)
        if ((Test-GleicherPfad $eltern $Ctx.RootDir) -and (Split-Path -Leaf $w.Path) -like '_gate-*') {
            Write-Host "entferne verwaisten temporären Gate-Worktree $($w.Path)"
            $grund = Remove-WorktreeLinks $w.Path
            if ($grund) { Stop-Wt 12 'BLOCKIERT' "verwaister Gate-Worktree $($w.Path): $grund – nichts gelöscht" }
            $r = Invoke-Git $Ctx.Main @('worktree', 'remove', '--force', $w.Path)
            if ($r.Code -ne 0) { Write-Host "WARNUNG: nicht entfernt: $(Get-GitKurz $r)" }
        }
    }
    # nicht registrierte Reste (git hat die Registrierung gelöscht, ein Prozess hielt den Ordner)
    if (-not (Test-Path -LiteralPath $Ctx.RootDir -PathType Container)) { return }
    $registriert = @(Get-Worktrees $Ctx.Main)
    foreach ($d in @(Get-ChildItem -LiteralPath $Ctx.RootDir -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($d.Name -notmatch '^_gate-\d+$') { continue }
        if (@($registriert | Where-Object { Test-GleicherPfad $_.Path $d.FullName }).Count) { continue }
        if ($d.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            Write-Host "WARNUNG: $($d.FullName) ist ein Link – nicht entfernt"
            continue
        }
        $grund = Remove-WorktreeLinks $d.FullName
        if ($grund) { Stop-Wt 12 'BLOCKIERT' "nicht registrierter Gate-Rest $($d.FullName): $grund – nichts gelöscht" }
        try {
            [IO.Directory]::Delete($d.FullName, $true)
            Write-Host "nicht registrierten Gate-Rest entfernt: $($d.FullName)"
        } catch {
            Write-Host "WARNUNG: nicht registrierter Gate-Rest $($d.FullName) nicht (vollständig) entfernt: $($_.Exception.Message)"
        }
    }
}

function Get-AbweichendeDateien($Ctx, $Stand) {
    # genannte Dateien, deren Arbeitskopie nicht mehr dem gegateten Stand entspricht
    foreach ($f in @($Stand.Keys)) {
        $soll = if ($null -eq $Stand[$f]) { '-' } else { $Stand[$f].Hash }
        $p = Join-Path $Ctx.Main $f
        $jetzt = '-'
        if (Test-Path -LiteralPath $p -PathType Leaf) {
            try { $jetzt = Get-InhaltsHash ([IO.File]::ReadAllBytes($p)) } catch { $jetzt = '?' }
        }
        if ($jetzt -ne $soll) { $f }
    }
}

function Get-BaumEintraege([string]$Wurzel, [string]$Rev, [string[]]$Liste) {
    # Modus und Blob je Pfad in $Rev bzw. im Index (nur vorhandene Pfade)
    $e = @{}
    if ($Rev) {
        $r = Invoke-Git $Wurzel (@('ls-tree', '-z', $Rev, '--') + $Liste)
        if ($r.Code -eq 0) {
            foreach ($z in Split-Nul $r.Out) {
                if ($z -match '^(\d{6}) (\w+) ([0-9a-f]+)\t(.+)$') { $e[$Matches[4]] = [pscustomobject]@{ Modus = $Matches[1]; Blob = $Matches[3] } }
            }
        }
    } else {
        $r = Invoke-Git $Wurzel (@('ls-files', '-s', '-z', '--') + $Liste)
        if ($r.Code -eq 0) {
            foreach ($z in Split-Nul $r.Out) {
                if ($z -match '^(\d{6}) ([0-9a-f]+) 0\t(.+)$') { $e[$Matches[3]] = [pscustomobject]@{ Modus = $Matches[1]; Blob = $Matches[2] } }
            }
        }
    }
    return $e
}

function Format-CommitNachricht([string]$Text) {
    # wie git commit -m (cleanup whitespace): Leerraum am Zeilenende und Rand-Leerzeilen weg, Leerzeilen zusammenfassen
    $aus = [System.Collections.Generic.List[string]]::new()
    foreach ($z in (($Text -replace "`r`n", "`n") -split "`n")) {
        $z = $z.TrimEnd()
        if ($z -eq '' -and ($aus.Count -eq 0 -or $aus[$aus.Count - 1] -eq '')) { continue }
        $aus.Add($z)
    }
    while ($aus.Count -and $aus[$aus.Count - 1] -eq '') { $aus.RemoveAt($aus.Count - 1) }
    return (($aus -join "`n") + "`n")
}

function New-GegateterCommit($Ctx, [string]$Basis, $Stand) {
    # committet genau die gegateten Blobs auf $Basis: temporärer Index, write-tree, commit-tree, update-ref mit
    # Altwert (Vergleich-und-Tausch); danach im echten Index nur die genannten Pfade auf den neuen Commit setzen
    # (Arbeitskopie unangetastet). Git-Hooks laufen dabei nicht. Aufruf unter main.lock.
    $hb = $Ctx.Cfg.hauptbranch
    $liste = [string[]]@($Stand.Keys)
    [void][IO.Directory]::CreateDirectory($Ctx.LockDir)
    $idx = Join-Path $Ctx.LockDir "gate-index-$PID"
    $nachrichtDatei = Join-Path $Ctx.LockDir "gate-nachricht-$PID.txt"
    $umg = @{ GIT_INDEX_FILE = $idx }
    $neu = ''
    try {
        foreach ($p in @($idx, "$idx.lock")) { if ([IO.File]::Exists($p)) { [IO.File]::Delete($p) } }
        [void](Invoke-GitOk $Ctx.Main @('read-tree', $Basis) $umg)
        $dazu = [System.Collections.Generic.List[string]]::new()
        $weg = [System.Collections.Generic.List[string]]::new()
        foreach ($f in $liste) {
            $e = $Stand[$f]
            if ($null -eq $e) { $weg.Add($f) } else { $dazu.Add('--cacheinfo'); $dazu.Add("$($e.Modus),$($e.Blob),$f") }
        }
        # erst entfernen, dann hinzufügen (eine genannte Datei kann einem genannten Ordner Platz machen)
        if ($weg.Count) { [void](Invoke-GitOk $Ctx.Main (@('update-index', '--force-remove', '--') + $weg.ToArray()) $umg) }
        if ($dazu.Count) { [void](Invoke-GitOk $Ctx.Main (@('update-index', '--add') + $dazu.ToArray()) $umg) }
        $tree = First (Invoke-GitOk $Ctx.Main @('write-tree') $umg).Lines
        if ($tree -eq (First (Invoke-GitOk $Ctx.Main @('rev-parse', "$Basis^{tree}")).Lines)) {
            Stop-Wt 14 'NICHTS' 'keine Änderungen an den genannten Dateien'
        }
        [IO.File]::WriteAllText($nachrichtDatei, (Format-CommitNachricht $Nachricht), $script:Utf8)
        $ct = @('commit-tree', $tree, '-p', $Basis, '-F', $nachrichtDatei)
        if ((First (Invoke-Git $Ctx.Main @('config', '--bool', 'commit.gpgsign')).Lines) -eq 'true') { $ct += '-S' }
        $r = Invoke-Git $Ctx.Main $ct
        if ($r.Code -ne 0) {
            Write-GitZeilen $r
            Stop-Wt 12 'BLOCKIERT' "git commit-tree fehlgeschlagen: $(Get-GitKurz $r) – nichts committet"
        }
        $neu = First $r.Lines
        $titel = (Format-CommitNachricht $Nachricht).Split("`n")[0]
        for ($i = 0; ; $i++) {
            $u = Invoke-Git $Ctx.Main @('update-ref', '-m', "commit (wt commit -Gate): $titel", "refs/heads/$hb", $neu, $Basis)
            if ($u.Code -eq 0) { break }
            $jetzt = First (Invoke-Git $Ctx.Main @('rev-parse', '-q', '--verify', "refs/heads/$hb")).Lines
            if ($jetzt -ne $Basis) {
                Write-GitZeilen $u
                Stop-Wt 12 'BLOCKIERT' "$hb hat sich beim Commit bewegt ($(Kurz $jetzt) statt $(Kurz $Basis)) – nichts committet"
            }
            if ($i -lt 3) { Write-Host "Ref-Sperre von $hb belegt – neuer Versuch in 3 s"; Start-Sleep -Seconds 3; continue }
            Write-GitZeilen $u
            Stop-Wt 12 'BLOCKIERT' "update-ref fehlgeschlagen: $(Get-GitKurz $u) – nichts committet"
        }
    } finally {
        foreach ($p in @($idx, "$idx.lock", $nachrichtDatei)) { try { if ([IO.File]::Exists($p)) { [IO.File]::Delete($p) } } catch { } }
    }
    # echter Index: nur die genannten Pfade auf den neuen Commit, sonst stünden sie als Rückwärts-Diff gestagt
    for ($i = 0; ; $i++) {
        $r = Invoke-Git $Ctx.Main (@('reset', '-q', $neu, '--') + $liste)
        if ($r.Code -eq 0) { break }
        if ((($r.Out + "`n" + $r.Err) -match 'index\.lock') -and $i -lt 3) {
            Write-Host 'index.lock im Hauptcheckout belegt – neuer Versuch in 3 s'
            Start-Sleep -Seconds 3
            continue
        }
        Write-GitZeilen $r
        Stop-Wt 13 'TEILZUSTAND' ("Commit {0} auf {1} angelegt, Indexeinträge der genannten Pfade nicht angeglichen ({2}) – im Hauptcheckout nichts committen; Mensch: git reset -q -- {3}" -f (Kurz $neu), $hb, (Get-GitKurz $r), ($liste -join ' '))
    }
    return $neu
}

function Invoke-GateCommit($Ctx, [string[]]$Liste) {
    $cfg = $Ctx.Cfg
    if ($null -eq $cfg.gate) {
        Stop-Wt 12 'BLOCKIERT' "Projektwert 'gate' fehlt in .ai-sdlc/arbeitsbaeume.json (`"`" heißt bewusst keine Gate-Kette)"
    }
    if ($cfg.gate -eq '') {
        Write-Host 'keine Gate-Kette (Projektwert leer)'
        return (Invoke-HauptCommit $Ctx $Liste)
    }
    # früh (ohne Sperre) prüfen, damit Aufruffehler und Dubletten keinen Gate-Lauf kosten; endgültig unter main.lock
    $pb = Get-PfadBekannt $Ctx.Main $Liste
    Assert-KeineHalbeUmbenennung $Ctx.Main $Liste $pb.ImHead
    Assert-NummernHauptCommit $Ctx $Liste
    # wie git add -N: eine neue, ignorierte Datei wird nicht committet (update-index fragte nicht danach)
    foreach ($f in $pb.Neu) {
        $ci = Invoke-Git $Ctx.Main @('check-ignore', '-q', '--', $f)
        if ($ci.Code -eq 0) { Stop-Wt 12 'BLOCKIERT' "Datei ist gitignoriert: $f – nichts committet" }
    }
    foreach ($f in $Liste) {
        $p = Join-Path $Ctx.Main $f
        if ((Test-Path -LiteralPath $p) -and ([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint)) {
            Stop-Wt 12 'BLOCKIERT' "commit -Gate übernimmt keine Links (Junction/Symlink): $f"
        }
    }
    $inhaber = Join-Path $Ctx.LockDir 'integration.owner'
    $sperre = Lock-Datei (Join-Path $Ctx.LockDir 'integration.lock') ($cfg.sperreWartenMinuten * 60) 'Integrationssperre' $inhaber
    try {
        Assert-KeinVerwaistesGate $inhaber
        Write-Inhaber $inhaber 'commit -Gate (Hauptcheckout)'
        $n = 1
        for ($v = 1; $v -le $n; $v++) {
            Update-KontextKonfig $Ctx
            $cfg = $Ctx.Cfg
            $n = $cfg.integrationsVersuche
            if ($null -eq $cfg.gate) {
                Stop-Wt 12 'BLOCKIERT' "Projektwert 'gate' fehlt inzwischen in .ai-sdlc/arbeitsbaeume.json – nichts committet"
            }
            if ($cfg.gate -eq '') {
                Write-Host 'keine Gate-Kette (Projektwert inzwischen leer)'
                return (Invoke-HauptCommit $Ctx $Liste)
            }
            if ($v -eq 1) { Remove-VerwaisteGateWorktrees $Ctx }
            Assert-HauptAufHauptbranch $Ctx
            $h0 = First (Invoke-GitOk $Ctx.Main @('rev-parse', 'HEAD')).Lines
            $tmp = Join-Path $Ctx.RootDir "_gate-$PID"
            if (Test-Path -LiteralPath $tmp) { Stop-Wt 12 'BLOCKIERT' "temporärer Gate-Ordner existiert bereits: $tmp" }
            Write-Host "Versuch $v/${n}: Gate in temporärem Worktree auf $(Kurz $h0) plus genannte Dateien"
            $r = Invoke-Git $Ctx.Main @('worktree', 'add', '--detach', $tmp, $h0)
            if ($r.Code -ne 0) {
                Write-GitZeilen $r
                Stop-Wt 12 'BLOCKIERT' "temporärer Worktree nicht anlegbar: $(Get-GitKurz $r)"
            }
            $code = 1
            $log = ''
            $nichts = $false
            $abbau = $null
            # gegateter Stand je genannter Datei: Blob (per hash-object -w festgehalten), Modus und Inhalts-Hash
            # der Arbeitskopie beim Kopieren; $null = gelöscht
            $stand = [ordered]@{}
            try {
                $imIndex = Get-BaumEintraege $Ctx.Main '' $Liste
                $imHead = Get-BaumEintraege $Ctx.Main $h0 $Liste
                $hashes = @{}
                foreach ($f in $Liste) {
                    $quelle = Join-Path $Ctx.Main $f
                    $zielPfad = Join-Path $tmp $f
                    if (Test-Path -LiteralPath $quelle -PathType Leaf) {
                        $bytes = $null
                        try { $bytes = [IO.File]::ReadAllBytes($quelle) } catch { Stop-Wt 12 'BLOCKIERT' "Datei nicht lesbar: $f ($($_.Exception.Message))" }
                        try {
                            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName((Norm $zielPfad)))
                            [IO.File]::WriteAllBytes($zielPfad, $bytes)
                        } catch {
                            $grund = if ($null -ne $_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
                            Stop-Wt 12 'BLOCKIERT' "Datei nicht in den temporären Worktree übertragbar (Datei/Ordner-Konflikt mit HEAD?): $f ($grund) – nichts committet"
                        }
                        $hashes[$f] = Get-InhaltsHash $bytes
                    } elseif (Test-Path -LiteralPath $zielPfad -PathType Leaf) {
                        [IO.File]::Delete($zielPfad)
                    }
                }
                # Blobs erst nach dem Kopieren aller Dateien (eine genannte .gitattributes gilt dann schon), aus genau
                # den kopierten Bytes mit den Filtern laut Pfad (wie git add) und vor dem Gate, das sie ändern könnte
                foreach ($f in $Liste) {
                    if (-not $hashes.ContainsKey($f)) { $stand[$f] = $null; continue }
                    $modus = if ($imIndex.ContainsKey($f)) { $imIndex[$f].Modus } elseif ($imHead.ContainsKey($f)) { $imHead[$f].Modus } else { '100644' }
                    if ($modus -eq '160000') { Stop-Wt 12 'BLOCKIERT' "commit -Gate übernimmt keine Submodule: $f" }
                    $blob = First (Invoke-GitOk $tmp @('hash-object', '-w', '--', $f)).Lines
                    $stand[$f] = [pscustomobject]@{ Blob = $blob; Modus = $modus; Hash = $hashes[$f] }
                }
                $aenderung = $false
                foreach ($f in $Liste) {
                    $e = $stand[$f]
                    $alt = if ($imHead.ContainsKey($f)) { $imHead[$f] } else { $null }
                    if ($null -eq $e) { if ($null -ne $alt) { $aenderung = $true } }
                    elseif ($null -eq $alt -or $alt.Blob -ne $e.Blob -or $alt.Modus -ne $e.Modus) { $aenderung = $true }
                }
                if (-not $aenderung) {
                    $nichts = $true
                } else {
                    Copy-WorktreeInclude $Ctx $tmp
                    $logDir = Initialize-GateLogDir $Ctx $Ctx.Main
                    Invoke-Setup $Ctx $tmp $logDir $inhaber
                    $log = New-LogPfad $logDir 'wt-gate'
                    Write-Host "Gate läuft im temporären Worktree (Log: $log)"
                    $code = Invoke-Befehlszeile $tmp $cfg.gate $log $inhaber
                }
            } finally {
                $abbau = Remove-GateWorktree $Ctx $tmp
            }
            if ($abbau) {
                $gateText = if ($nichts) { 'kein Gate-Lauf' } elseif ($code -eq 0) { 'Gate grün' } else { "Gate rot (Exitcode $code)" }
                Stop-Wt 12 'BLOCKIERT' "temporärer Gate-Worktree $tmp nicht abgebaut ($abbau; $gateText) – nichts gelöscht, nichts committet"
            }
            if ($nichts) { Stop-Wt 14 'NICHTS' 'keine Änderungen an den genannten Dateien' }
            if ($code -ne 0) {
                Show-LogEnde $log
                Stop-Wt 11 'ROT' "Gate rot (Exitcode $code); nichts committet; Log: $log"
            }
            $sha = ''
            $mainSperre = Lock-Datei (Join-Path $Ctx.LockDir 'main.lock') 120 'Hauptcheckout-Sperre' ''
            try {
                Assert-HauptAufHauptbranch $Ctx
                $h1 = First (Invoke-GitOk $Ctx.Main @('rev-parse', 'HEAD')).Lines
                $nochmal = $false
                if ($h1 -ne $h0) {
                    $pf = @(Split-Nul (Invoke-GitOk $Ctx.Main @('diff', '--name-only', '-z', '--no-renames', '--ignore-submodules=none',
                                '--no-ext-diff', '--no-relative', $h0, $h1)).Out)
                    $rel = @($pf | Where-Object { -not (Test-PfadTreffer $_ $cfg.gateIrrelevant) })
                    $genannt = @($pf | Where-Object { $Liste -contains $_ })
                    $t0 = First (Invoke-GitOk $Ctx.Main @('rev-parse', "$h0^{tree}")).Lines
                    $t1 = First (Invoke-GitOk $Ctx.Main @('rev-parse', "$h1^{tree}")).Lines
                    if ($pf.Count -eq 0 -and $t0 -ne $t1) {
                        $nochmal = $true
                        Write-Host 'HEAD hat sich während des Gates bewegt (anderer Tree, leerer Diff) – neuer Lauf'
                    } elseif ($rel.Count) {
                        $nochmal = $true
                        Write-Host "HEAD hat sich während des Gates bewegt ($($rel.Count) gate-relevante Pfade) – neuer Lauf"
                    } elseif ($genannt.Count) {
                        # der gegatete Blob überschriebe den inzwischen committeten Stand
                        $nochmal = $true
                        Write-Host "HEAD hat sich während des Gates bewegt und ändert genannte Dateien ($($genannt -join ', ')) – neuer Lauf"
                    } else {
                        Write-Host 'HEAD hat sich während des Gates bewegt, nur gate-irrelevante Pfade – Ergebnis gilt'
                    }
                }
                if (-not $nochmal) {
                    $abweichend = @(Get-AbweichendeDateien $Ctx $stand)
                    if ($abweichend.Count) {
                        Write-Host ("Hinweis: nach dem Kopieren für das Gate geändert: {0} – committet wird der gegatete Stand, die Änderung bleibt uncommittet" -f ($abweichend -join ', '))
                    }
                    $vorhanden = @{}
                    foreach ($f in $Liste) { $vorhanden[$f] = ($null -ne $stand[$f]) }
                    Assert-NummernHauptCommit $Ctx $Liste $vorhanden
                    $sha = New-GegateterCommit $Ctx $h1 $stand
                }
            } finally {
                $mainSperre.Dispose()
            }
            if ($sha) {
                $rest = @(Get-StatusPfade $Ctx.Main $Liste)
                if ($rest.Count) {
                    Write-Host ("Hinweis: Arbeitskopie weicht vom gegateten Commit ab, bleibt uncommittet: {0}" -f ($rest -join ', '))
                    $script:CommitZusatz = " (uncommittet geblieben: $($rest -join ', '))"
                }
                return $sha
            }
        }
        Stop-Wt 12 'BLOCKIERT' "nach $n Gate-Läufen nicht committet – $($cfg.hauptbranch) bewegt sich laufend"
    } finally {
        Unlock-Integration $sperre
    }
}

function Invoke-CmdCommit($Ctx) {
    if (-not $Nachricht -or -not $Nachricht.Trim()) { Stop-Wt 1 'FEHLER' 'commit braucht -Nachricht' }
    $liste = @(Get-DateiListe $Ctx.Top)
    if ($Gate -and -not $Ctx.IsMain) { Stop-Wt 1 'FEHLER' '-Gate gibt es nur im Hauptcheckout' }
    $mitKonfig = $Ctx.IsMain -and @($liste | Where-Object {
            [string]::Equals($_, $script:KonfigRel, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
    if ($Ctx.KonfigFehler -and -not ($mitKonfig -and $liste.Count -eq 1)) {
        # ungültige Konfiguration in HEAD: nur der Commit genau dieser Datei im Hauptcheckout läuft
        Stop-Wt 1 'FEHLER' "$($Ctx.KonfigFehler) (Projektwerte aus HEAD nicht verwendbar; erlaubt ist nur wt commit $($script:KonfigRel) im Hauptcheckout)"
    }
    if ($mitKonfig) {
        # Commit der Konfiguration: Arbeitskopie vollständig prüfen; Hauptbranch-Prüfung gegen ihren Wert
        $Ctx.KonfigCommit = $true
        $hbAlt = if ($Ctx.KonfigFehler) { '' } else { $Ctx.Cfg.hauptbranch }
        $cfgNeu = Get-KonfigFuerKonfigCommit $Ctx ([pscustomobject]@{ Cfg = $Ctx.Cfg; Fehler = $Ctx.KonfigFehler })
        if ($cfgNeu.hauptbranch -cne $hbAlt) {
            $aktuell = Get-AktuellerBranch $Ctx.Main
            if ($aktuell -cne $cfgNeu.hauptbranch) {
                $zeige = if ($aktuell) { $aktuell } else { '(detached HEAD)' }
                Stop-Wt 12 'BLOCKIERT' "geänderter Projektwert 'hauptbranch' ('$($cfgNeu.hauptbranch)') entspricht nicht dem aktuellen Branch des Hauptcheckouts ('$zeige') – nichts committet"
            }
        }
        Set-KontextKonfig $Ctx $cfgNeu
        if ($Ctx.KonfigFehler) {
            Write-Host 'Hinweis: Projektwerte aus HEAD nicht verwendbar – dieser Lauf verwendet die geprüfte Arbeitskopie'
        } elseif ($Ctx.KonfigAbweichung) {
            Write-Host 'Hinweis: committet die geänderte Konfiguration (Arbeitskopie geprüft); dieser Lauf verwendet noch die Werte aus HEAD, hauptbranch aus der Arbeitskopie'
        }
    } else {
        Assert-KonfigUnveraendert $Ctx
    }
    $cfg = $Ctx.Cfg
    $hb = $cfg.hauptbranch
    $titel = ($Nachricht -split "`r?`n")[0]
    if ($Ctx.IsMain) {
        Assert-HauptAufHauptbranch $Ctx
        if ($Gate) { $sha = Invoke-GateCommit $Ctx $liste }
        else { $sha = Invoke-HauptCommit $Ctx $liste }
        Stop-Wt 0 'OK' ("Commit {0} auf {1}: {2}{3}" -f (Kurz $sha), $Ctx.Cfg.hauptbranch, $titel, $script:CommitZusatz)
    }
    $branch = Get-AktuellerBranch $Ctx.Top
    if (-not $branch) { Stop-Wt 12 'BLOCKIERT' 'Checkout hat keinen Branch (detached HEAD) – kein Commit' }
    if ($branch -ceq $hb) { Stop-Wt 12 'BLOCKIERT' "Worktree steht auf $hb – Commits nur auf dem Issue-Branch" }
    $verstoesse = @(Get-NurAufMainVerstoesse $cfg $liste)
    if ($verstoesse.Count) {
        Stop-Wt 12 'BLOCKIERT' ("nurAufMain-Dateien nur im Hauptcheckout committen: {0}" -f ($verstoesse -join ', '))
    }
    $sha = Invoke-PfadCommit $Ctx.Top $liste
    Stop-Wt 0 'OK' ("Commit {0} auf {1}: {2}" -f (Kurz $sha), $branch, $titel)
}

function Assert-NichtImWorktree([string]$WtDir) {
    # das Verzeichnis des Aufrufers hielte den Ordner offen; worktree remove bliebe halb stecken
    $start = $script:StartVerzeichnis
    $drin = Test-PfadUnter $start $WtDir
    if (-not $drin -and [IO.Directory]::Exists($start)) {
        $t = Invoke-Git $start @('rev-parse', '--show-toplevel')
        if ($t.Code -eq 0 -and (First $t.Lines) -and (Test-GleicherPfad (First $t.Lines) $WtDir)) { $drin = $true }
    }
    if ($drin) {
        Stop-Wt 12 'BLOCKIERT' "aktuelles Verzeichnis liegt im zu entfernenden Worktree $WtDir – aus dem Hauptcheckout mit -Key aufrufen"
    }
}

function Test-InitialisierteSubmodule([string]$Dir) {
    if (-not (Test-Path -LiteralPath (Join-Path $Dir '.gitmodules') -PathType Leaf)) { return $false }
    $r = Invoke-Git $Dir @('submodule', 'status', '--recursive')
    if ($r.Code -ne 0) { return $true }
    foreach ($z in $r.Lines) { if ($z.Length -gt 0 -and $z[0] -ne '-') { return $true } }
    return $false
}

function Find-ProbeOrdner([string]$Dir) {
    # Ordner einer gescheiterten Belegungsprobe von finish: <dir>.wt-probe-<pid>
    $eltern = Split-Path -Parent $Dir
    if (-not (Test-Path -LiteralPath $eltern -PathType Container)) { return }
    $praefix = (Split-Path -Leaf $Dir) + '.wt-probe-'
    foreach ($d in @(Get-ChildItem -LiteralPath $eltern -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($d.Name.StartsWith($praefix, [StringComparison]::OrdinalIgnoreCase)) { $d.FullName }
    }
}

function Get-ProbeHinweis([string]$Dir, [string[]]$Proben) {
    $p = $Proben[0]
    if (Test-Path -LiteralPath $Dir) {
        return "Ordner einer früheren Belegungsprobe vorhanden: $p (neben $Dir) – prüfen, welcher Ordner der Worktree ist; Mensch"
    }
    return "Worktree-Ordner liegt unter ${p}: eine Belegungsprobe von finish ließ sich nicht zurückbenennen (Exit 13) – nach $Dir zurückbenennen, nicht 'git worktree prune' (verwirft die Registrierung); Mensch"
}

function Assert-KeineProbeReste([string]$Dir) {
    $proben = @(Find-ProbeOrdner $Dir)
    if ($proben.Count) { Stop-Wt 12 'BLOCKIERT' (Get-ProbeHinweis $Dir $proben) }
}

function Assert-KeineProgrammeImWorktree([string]$Dir) {
    # ein laufendes Programm aus dem Worktree verhindert das Umbenennen nicht, wohl aber das Löschen: git hätte
    # dann schon Registrierung und Dateien entfernt, bevor es scheitert
    $treffer = [System.Collections.Generic.List[string]]::new()
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        $pfad = $null
        try { $pfad = $p.Path } catch { $pfad = $null }
        if ($pfad -and (Test-PfadUnter $pfad $Dir)) { $treffer.Add("PID $($p.Id): $pfad") }
    }
    if ($treffer.Count) {
        Write-Host 'Programme aus dem Worktree laufen noch:'
        $treffer | Select-Object -First 20 | ForEach-Object { Write-Host "  $_" }
        Stop-Wt 12 'BLOCKIERT' ("Programme aus dem Worktree laufen noch ({0}) – beenden, dann erneut aufrufen; nichts gelöscht" -f (@($treffer | Select-Object -First 5) -join '; '))
    }
}

function Test-OrdnerFrei([string]$Dir) {
    # Belegungsprobe ohne Löschen: laufende Programme aus dem Worktree, dann umbenennen und zurück; ein offener
    # Prozess (Arbeitsverzeichnis, offene Datei) verhindert das Umbenennen
    Assert-KeineProgrammeImWorktree $Dir
    $probe = "$($Dir).wt-probe-$PID"
    if (Test-Path -LiteralPath $probe) { Stop-Wt 12 'BLOCKIERT' "Probe-Ordner $probe existiert bereits – prüfen, Mensch" }
    try {
        [IO.Directory]::Move($Dir, $probe)
    } catch {
        $grund = if ($null -ne $_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Stop-Wt 12 'BLOCKIERT' "Worktree-Ordner belegt – Fenster/Prozesse schließen, dann erneut aufrufen; nichts gelöscht ($grund)"
    }
    for ($i = 0; $i -lt 20; $i++) {
        try {
            [IO.Directory]::Move($probe, $Dir)
            return
        } catch {
            Start-Sleep -Milliseconds 250
        }
    }
    Stop-Wt 13 'TEILZUSTAND' "Belegungsprobe von finish: Worktree-Ordner liegt jetzt unter $probe und ließ sich nicht zurückbenennen (Teilzustand der Probe, nichts gelöscht) – nach $Dir zurückbenennen, nicht 'git worktree prune'; Mensch"
}

function Get-IgnorierteOberste([string]$Dir, [string]$Ablage) {
    # ignorierte Einträge der obersten Ebene, die worktree remove mitlöscht (ohne die gesicherte Ablage)
    $r = Invoke-Git $Dir @('status', '--porcelain', '--ignored', '-unormal', '--ignore-submodules=none')
    if ($r.Code -ne 0) { return }
    $ablErster = @($Ablage -split '/')[0]
    foreach ($z in $r.Lines) {
        if (-not $z.StartsWith('!! ')) { continue }
        $p = $z.Substring(3).Trim('"')
        $kern = $p.TrimEnd('/')
        if ($kern.Contains('/')) { continue }
        if ([string]::Equals($kern, $ablErster, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $p
    }
}

function Invoke-CmdFinish($Ctx) {
    $cfg = $Ctx.Cfg
    $hb = $cfg.hauptbranch
    Assert-KonfigUnveraendert $Ctx
    Assert-HauptAufHauptbranch $Ctx
    $k = Resolve-Key $Ctx
    $wtDir = Get-WtDir $Ctx $k
    $wt = Find-Worktree $Ctx $wtDir
    # gescheiterte Rückbenennung einer früheren Belegungsprobe (Exit 13): zurückbenennen, nicht prune
    Assert-KeineProbeReste $wtDir
    if (Test-Path -LiteralPath $wtDir) { Assert-NichtImWorktree $wtDir }
    $branch = ''
    $restOrdner = $false
    if ($null -ne $wt) {
        if ($wt.Prunable -or -not (Test-Path -LiteralPath $wtDir -PathType Container)) {
            Stop-Wt 12 'BLOCKIERT' "Worktree $wtDir ist registriert, der Ordner fehlt – 'git worktree prune' durch den Menschen"
        }
        Assert-KeineOperation $wtDir "Worktree $k"
        $branch = Get-AktuellerBranch $wtDir
        if (-not $branch) { Stop-Wt 12 'BLOCKIERT' "Worktree $k hat keinen Branch (detached HEAD)" }
    } else {
        $kandidaten = @(Find-KeyBranches $Ctx $k)
        if ($kandidaten.Count -gt 1) { Stop-Wt 12 'BLOCKIERT' ("mehrere Branches für {0}: {1}" -f $k, ($kandidaten -join ', ')) }
        if ($kandidaten.Count -eq 1) { $branch = $kandidaten[0] }
        if (Test-Path -LiteralPath $wtDir) {
            # Wiederholfall: ein früherer Abbau hat Inhalt und Registrierung gelöscht, der leere Ordner blieb
            $leer = (Test-Path -LiteralPath $wtDir -PathType Container) -and
                (@(Get-ChildItem -LiteralPath $wtDir -Force -ErrorAction SilentlyContinue).Count -eq 0)
            $integriert = $branch -and ($branch -cne $hb) -and
                ((Invoke-Git $Ctx.Main @('merge-base', '--is-ancestor', "refs/heads/$branch", "refs/heads/$hb")).Code -eq 0)
            if (-not ($leer -and $integriert)) {
                $grund = if (-not $leer) { 'nicht leer' } elseif (-not $branch) { 'kein Branch für den Key' } else { "Branch $branch nicht in $hb enthalten" }
                Stop-Wt 12 'BLOCKIERT' "Ordner $wtDir existiert, ist aber kein registrierter Worktree ($grund)"
            }
            $restOrdner = $true
        }
    }
    if ($null -eq $wt -and -not $branch) { Stop-Wt 14 'NICHTS' "weder Worktree noch Branch für $k vorhanden" }
    if ($branch -ceq $hb) { Stop-Wt 12 'BLOCKIERT' "Worktree $k steht auf $hb" }

    $anc = Invoke-Git $Ctx.Main @('merge-base', '--is-ancestor', "refs/heads/$branch", "refs/heads/$hb")
    if ($anc.Code -ne 0) {
        $vor = Get-Anzahl $Ctx.Main "refs/heads/$hb..refs/heads/$branch"
        Stop-Wt 12 'BLOCKIERT' "Branch $branch ist nicht vollständig in $hb integriert ($vor Commits offen) – zuerst wt integrate"
    }

    if ($restOrdner) {
        Set-Location -LiteralPath $Ctx.Main
        [Environment]::CurrentDirectory = $Ctx.Main
        try {
            [IO.Directory]::Delete($wtDir, $false)
        } catch {
            $grund = if ($null -ne $_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
            Stop-Wt 12 'BLOCKIERT' "leerer Rest-Ordner $wtDir nicht entfernbar – Fenster/Prozesse schließen ($grund)"
        }
        Write-Host "leeren Rest-Ordner eines früheren Abbaus entfernt: $wtDir"
    }

    if ($null -ne $wt) {
        $abl = $cfg.gateAblage
        Assert-Sauber $wtDir "Worktree $k" $abl
        $mitSubmodulen = Test-InitialisierteSubmodule $wtDir
        if ($mitSubmodulen) {
            $sm = Invoke-Git $wtDir @('submodule', 'foreach', '--quiet', '--recursive', 'git', 'status', '--porcelain', '-uall', '--ignore-submodules=none')
            if ($sm.Code -ne 0 -or @($sm.Lines).Count) {
                Write-Host 'Submodule im Worktree nicht sauber:'
                Write-GitZeilen $sm
                Stop-Wt 12 'BLOCKIERT' "Submodule im Worktree $k nicht sauber – nichts entfernt"
            }
        }
        $zielDir = Join-Path $Ctx.Main "$abl/_worktrees/$k"
        $plan = [System.Collections.Generic.List[object]]::new()
        $konflikte = [System.Collections.Generic.List[string]]::new()
        $quelle = Join-Path $wtDir $abl
        if (Test-Path -LiteralPath $quelle -PathType Container) {
            foreach ($f in Get-ChildItem -LiteralPath $quelle -Recurse -File -Force) {
                $rel = [IO.Path]::GetRelativePath($quelle, $f.FullName)
                $ziel = Join-Path $zielDir $rel
                if (Test-Path -LiteralPath $ziel -PathType Leaf) {
                    if ((Get-DateiHash $f.FullName) -ne (Get-DateiHash $ziel)) { $konflikte.Add($ziel) }
                    continue
                }
                $plan.Add([pscustomobject]@{ Von = $f.FullName; Nach = $ziel })
            }
        }
        $einstWt = Join-Path $wtDir '.claude/settings.local.json'
        $einstHaupt = Join-Path $Ctx.Main '.claude/settings.local.json'
        $einstGesichert = ''
        if (Test-Path -LiteralPath $einstWt -PathType Leaf) {
            $abweichend = -not (Test-Path -LiteralPath $einstHaupt -PathType Leaf) -or
                ((Get-DateiHash $einstWt) -ne (Get-DateiHash $einstHaupt))
            if ($abweichend) {
                $ziel = Join-Path $zielDir 'settings.local.json'
                if (Test-Path -LiteralPath $ziel -PathType Leaf) {
                    if ((Get-DateiHash $einstWt) -ne (Get-DateiHash $ziel)) { $konflikte.Add($ziel) }
                } else {
                    $plan.Add([pscustomobject]@{ Von = $einstWt; Nach = $ziel })
                }
                $einstGesichert = $ziel
            }
        }
        if ($konflikte.Count) {
            Write-Host 'Abweichende Dateien in der Gate-Ablage vorhanden (nichts überschrieben):'
            $konflikte | ForEach-Object { Write-Host "  $_" }
            Stop-Wt 12 'BLOCKIERT' "Gate-Ablage $zielDir enthält abweichende Dateien ($($konflikte.Count))"
        }
        Set-Location -LiteralPath $Ctx.Main
        [Environment]::CurrentDirectory = $Ctx.Main
        # früh proben, damit ein belegter Ordner nichts sichert; unmittelbar vor dem Entfernen noch einmal
        Test-OrdnerFrei $wtDir
        # ignoriert (auch nach dem älteren .gitignore-Stand des Worktrees), damit worktree remove an einer nicht
        # ignorierten Ablage nicht scheitert
        Add-Ignoriert $Ctx $abl @($wtDir)
        if ($plan.Count) {
            [void](Initialize-GateLogDir $Ctx $Ctx.Main)
            foreach ($e in $plan) {
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName((Norm $e.Nach)))
                Copy-Item -LiteralPath $e.Von -Destination $e.Nach
            }
            Write-Host "Gate-Ablage gesichert: $($plan.Count) Datei(en) nach $(Norm $zielDir)"
        }
        if ($einstGesichert) {
            Write-Host "Hinweis: .claude/settings.local.json des Worktrees weicht vom Hauptcheckout ab – gesichert nach $(Norm $einstGesichert); bei Bedarf Berechtigungen übernehmen"
        }
        $ignoriert = @(Get-IgnorierteOberste $wtDir $abl)
        if ($ignoriert.Count) {
            Write-Host ("Hinweis: mit dem Worktree werden auch diese ignorierten Einträge gelöscht: {0}" -f (@($ignoriert | Select-Object -First 20) -join ', '))
        }
        Test-OrdnerFrei $wtDir
        # Junctions/Symlinks zuerst selbst entfernen: git folgte Junctions und leerte deren Ziel
        $grund = Remove-WorktreeLinks $wtDir
        if ($grund) { Stop-Wt 12 'BLOCKIERT' "Worktree $wtDir nicht entfernt: $grund – nichts gelöscht" }
        # --force nur bei initialisierten, nachweislich sauberen Submodulen (ohne lehnt git immer ab)
        $entfernen = if ($mitSubmodulen) { @('worktree', 'remove', '--force', $wtDir) } else { @('worktree', 'remove', $wtDir) }
        $r = Invoke-Git $Ctx.Main $entfernen
        if ($r.Code -ne 0) {
            Write-GitZeilen $r
            if (($r.Out + "`n" + $r.Err) -match 'contains modified or untracked files') {
                # git prüft vor dem Löschen; ungetrackt sind z. B. Dateien, die der .gitignore-Stand des Worktrees nicht kennt
                $offen = @(Get-StatusZeilen $wtDir)
                Write-Host 'Worktree enthält geänderte oder ungetrackte Dateien:'
                $offen | Select-Object -First 30 | ForEach-Object { Write-Host "  $_" }
                Stop-Wt 12 'BLOCKIERT' ("Worktree nicht entfernt, nichts gelöscht: geänderte oder ungetrackte Dateien ({0}: {1}) – committen, ignorieren oder entfernen, Mensch" -f $offen.Count, (@($offen | Select-Object -First 5) -join '; '))
            }
            Stop-Wt 12 'BLOCKIERT' "Worktree nicht entfernt: $(Get-GitKurz $r) – Fenster bzw. Prozesse im Worktree schließen und erneut aufrufen"
        }
        Write-Host "Worktree entfernt: $wtDir"
    }
    $r = Invoke-Git $Ctx.Main @('branch', '-d', $branch)
    if ($r.Code -ne 0) {
        Write-GitZeilen $r
        Stop-Wt 12 'BLOCKIERT' "Branch $branch nicht gelöscht: $(Get-GitKurz $r)"
    }
    $letzter = Join-Path $Ctx.LockDir ('gates/letzter-' + (ConvertTo-SicherName $branch) + '.txt')
    if (Test-Path -LiteralPath $letzter -PathType Leaf) { Remove-Item -LiteralPath $letzter -Force }
    $wtText = if ($null -ne $wt) { 'Worktree entfernt' } elseif ($restOrdner) { 'leerer Rest-Ordner entfernt' } else { 'kein Worktree vorhanden' }
    Stop-Wt 0 'OK' "$k abgeschlossen: $wtText, Branch $branch gelöscht"
}

function Format-Alter([datetime]$ZeitUtc) {
    $d = [DateTime]::UtcNow - $ZeitUtc
    if ($d.TotalMinutes -lt 1) { return 'vor <1 min' }
    if ($d.TotalHours -lt 1) { return "vor $([int][math]::Floor($d.TotalMinutes)) min" }
    if ($d.TotalDays -lt 1) { return "vor $([int][math]::Floor($d.TotalHours)) h" }
    return "vor $([int][math]::Floor($d.TotalDays)) d"
}

function Invoke-CmdStatus($Ctx) {
    $cfg = $Ctx.Cfg
    $hb = $cfg.hauptbranch
    $hbRef = "refs/heads/$hb"
    Write-Host "Hauptcheckout: $($Ctx.Main) (Hauptbranch $hb)"
    if ($Ctx.KonfigFehler) {
        Write-Host "WARNUNG: Projektwerte aus HEAD nicht verwendbar – $($Ctx.KonfigFehler); status verwendet Standardwerte, andere Befehle enden mit 1 (Korrektur: Datei im Hauptcheckout reparieren, dann wt commit $($script:KonfigRel))"
    }
    if ($Ctx.KonfigAbweichung) {
        Write-Host "WARNUNG: Konfiguration uncommittet geändert – $($script:KonfigRel) weicht von HEAD ab; verwendet werden die Werte aus HEAD, andere Befehle blockieren (12)"
    }
    if ((Invoke-Git $Ctx.Main @('rev-parse', '--verify', '-q', $hbRef)).Code -ne 0) {
        Write-Host "WARNUNG: Hauptbranch '$hb' existiert nicht (Projektwert hauptbranch prüfen)"
    }
    $ausgecheckt = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($w in $Ctx.Worktrees) {
        if ($w.Branch) { [void]$ausgecheckt.Add($w.Branch) }
        $eltern = Norm (Split-Path -Parent $w.Path)
        $name = if (Test-GleicherPfad $w.Path $Ctx.Main) { '(Hauptcheckout)' }
                elseif (Test-GleicherPfad $eltern $Ctx.RootDir) { Split-Path -Leaf $w.Path }
                else { $w.Path }
        if ($w.Prunable -or -not (Test-Path -LiteralPath $w.Path -PathType Container)) {
            $proben = @(Find-ProbeOrdner $w.Path)
            if ($proben.Count) {
                Write-Host "$name | Ordner fehlt – liegt unter $($proben[0]) (Belegungsprobe von finish, Exit 13): zurückbenennen, nicht 'git worktree prune'; Mensch | $($w.Path)"
            } else {
                Write-Host "$name | Ordner fehlt (prunable) | $($w.Path)"
            }
            continue
        }
        try {
            Write-WorktreeStatus $Ctx $w $name $ausgecheckt
        } catch [WtExit] {
            Write-Host "$name | Status nicht lesbar: $($_.Exception.Message) | $($w.Path)"
        }
    }
    if (Test-Path -LiteralPath $Ctx.RootDir -PathType Container) {
        foreach ($d in @(Get-ChildItem -LiteralPath $Ctx.RootDir -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($null -ne (Find-Worktree $Ctx $d.FullName)) { continue }
            $anzahl = @(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue).Count
            $inhalt = if ($anzahl -eq 0) { 'leer' } else { "$anzahl Einträge" }
            $rat = if ($d.Name -match '^(.+)\.wt-probe-\d+$') {
                " – Ordner einer gescheiterten Belegungsprobe: nach $($Matches[1]) zurückbenennen, nicht 'git worktree prune'; Mensch"
            } elseif ($d.Name -match '^_gate-\d+$') {
                ' – räumt der nächste wt commit -Gate ab'
            } elseif ($anzahl -gt 0) {
                ' – Rest entfernen, Mensch'
            } else { '' }
            Write-Host "Rest (nicht registriert): $(Norm $d.FullName) ($inhalt)$rat"
        }
    }
    $inhaberPfad = Join-Path $Ctx.LockDir 'integration.owner'
    switch (Get-SperrStatus (Join-Path $Ctx.LockDir 'integration.lock')) {
        'belegt' { Write-Host "Integrationssperre belegt – Inhaber: $(Get-InhaberText $inhaberPfad)" }
        'unbekannt' { Write-Host 'Integrationssperre: Sperrstatus nicht prüfbar (kein Lesezugriff)' }
        default {
            Write-Host 'Integrationssperre frei'
            $o = Get-InhaberDaten $inhaberPfad
            if ($null -ne $o -and $o['gatePid'] -and (Test-ProzessLaeuft $o['gatePid'] $o['gateStartTicks'])) {
                Write-Host "WARNUNG: verwaister Gate-Prozess läuft noch (PID $($o['gatePid']), Key $($o['key']))"
            }
        }
    }
    switch (Get-SperrStatus (Join-Path $Ctx.LockDir 'main.lock')) {
        'belegt' { Write-Host 'Hauptcheckout-Sperre belegt' }
        'unbekannt' { Write-Host 'Hauptcheckout-Sperre: Sperrstatus nicht prüfbar (kein Lesezugriff)' }
    }
    $nm = Invoke-Git $Ctx.Main @('for-each-ref', '--format=%(refname)', "--no-merged=$hbRef", 'refs/heads/')
    if ($nm.Code -eq 0) {
        foreach ($ref in $nm.Lines) {
            $b = $ref.Substring(11)
            if ($ausgecheckt.Contains($b)) { continue }
            $vor = Get-Anzahl $Ctx.Main "$hbRef..$ref"
            Write-Host "Branch ohne Worktree: $b (+$vor, nicht in $hb)"
        }
    }
    $me = Invoke-Git $Ctx.Main @('for-each-ref', '--format=%(refname)', "--merged=$hbRef", 'refs/heads/')
    if ($me.Code -eq 0) {
        foreach ($ref in $me.Lines) {
            $b = $ref.Substring(11)
            if ($b -ceq $hb -or $ausgecheckt.Contains($b) -or $b -notmatch '^([A-Za-z]+-[0-9]+)(-|$)') { continue }
            # ein nicht leerer, nicht registrierter Rest (z. B. halber Abbau) räumt finish nicht ab
            $hinweis = '(Abschluss: wt finish)'
            $kDir = Get-WtDir $Ctx ([regex]::Match($b, '^[A-Za-z]+-[0-9]+').Value.ToLowerInvariant())
            if (@(Find-ProbeOrdner $kDir).Count) {
                $hinweis = '(Ordner der Belegungsprobe zurückbenennen, Mensch)'
            } elseif ((Test-Path -LiteralPath $kDir -PathType Container) -and $null -eq (Find-Worktree $Ctx $kDir) -and
                @(Get-ChildItem -LiteralPath $kDir -Force -ErrorAction SilentlyContinue).Count) {
                $hinweis = "(Rest $kDir entfernen, Mensch)"
            }
            Write-Host "Branch integriert, ohne Worktree: $b $hinweis"
        }
    }
    Stop-Wt 0 'OK' "$($Ctx.Worktrees.Count) Worktree(s)"
}

function Get-RebaseBranch([string]$Dir) {
    $gd = Get-GitDir $Dir
    foreach ($d in @('rebase-merge', 'rebase-apply')) {
        $hn = Join-Path $gd "$d/head-name"
        if (Test-Path -LiteralPath $hn -PathType Leaf) {
            $ref = ([IO.File]::ReadAllText($hn)).Trim()
            if ($ref.StartsWith('refs/heads/')) { return $ref.Substring(11) }
        }
    }
    return ''
}

function Write-WorktreeStatus($Ctx, $w, [string]$name, $ausgecheckt) {
    $hb = $Ctx.Cfg.hauptbranch
    $hbRef = "refs/heads/$hb"
    $ops = @(Get-OffeneOperationen $w.Path)
    $br = if ($w.Branch) { $w.Branch } else { "detached $(Kurz $w.Head)" }
    if (-not $w.Branch -and $ops -contains 'REBASE') {
        $rb = Get-RebaseBranch $w.Path
        if ($rb) {
            [void]$ausgecheckt.Add($rb)
            $br = "$rb (Rebase läuft, detached $(Kurz $w.Head))"
        }
    }
    $lr = Invoke-Git $w.Path @('rev-list', '--left-right', '--count', "$hbRef...HEAD")
    $vr = '?'
    $integriert = $false
    if ($lr.Code -eq 0 -and (First $lr.Lines) -match '^(\d+)\s+(\d+)$') {
        $vr = "+$($Matches[2])/-$($Matches[1])"
        # Branch vollständig im Hauptbranch enthalten
        $integriert = $w.Branch -and $w.Branch -cne $hb -and [int]$Matches[2] -eq 0
    }
    $st = @(Get-StatusZeilen $w.Path)
    $zeit = $null
    $ct = Invoke-Git $w.Path @('log', '-1', '--format=%ct', 'HEAD')
    if ($ct.Code -eq 0 -and (First $ct.Lines) -match '^\d+$') {
        $zeit = [DateTimeOffset]::FromUnixTimeSeconds([long](First $ct.Lines)).UtcDateTime
    }
    foreach ($z in $st) {
        $p = $z.Substring(3)
        if ($p.Contains(' -> ')) { $p = @($p -split ' -> ')[-1] }
        $voll = Join-Path $w.Path $p.Trim('"')
        if (Test-Path -LiteralPath $voll -PathType Leaf) {
            $m = (Get-Item -LiteralPath $voll -Force).LastWriteTimeUtc
            if ($null -eq $zeit -or $m -gt $zeit) { $zeit = $m }
        }
    }
    $alter = if ($null -ne $zeit) { Format-Alter $zeit } else { '?' }
    $teile = @($name, $br, "$vr ggü. $hb")
    if ($integriert) { $teile += 'integriert' }
    $teile += "$($st.Count) uncommittet"
    if ($ops.Count) { $teile += ($ops -join '/') }
    if ($w.Locked) { $teile += 'gesperrt (worktree lock)' }
    $teile += "letzte Änderung $alter"
    $teile += $w.Path
    Write-Host ($teile -join ' | ')
}

function Show-Hilfe {
    @(
        'wt.ps1 – Issue-Worktrees für parallele Sessions (ai-sdlc, Arbeitsbaum-Modus)'
        'Aufruf: pwsh -NoProfile -File wt.ps1 <befehl> [-Key K] [-Slug s] [-Nachricht m] [-Gate] [-Repo pfad] [dateien…]'
        '  start -Key K [-Slug s]               Worktree anlegen bzw. wiederverwenden (+ sync)'
        '  sync [-Key K]                        Branch auf den Hauptbranch bringen (ff bzw. Rebase)'
        '  integrate [-Key K]                   Rebase → Prüfungen → Gate → ff in den Hauptbranch'
        '  commit -Nachricht m [-Gate] <dat…>   Pfadlisten-Commit; -Gate nur im Hauptcheckout (committet die gegateten Bytes, ohne Git-Hooks)'
        '  finish -Key K                        aus dem Hauptcheckout, nach Integration: Ablage sichern, Worktree und Branch entfernen'
        '  status                               Worktrees mit Pfad, Reste, Sperren, Branches ohne Worktree'
        'Ohne -Key gilt der Key des aktuellen Worktrees.'
        'Regeln: ~/.claude/ai-sdlc/arbeitsbaeume.md (Claude Code) bzw. ~/.codex/ai-sdlc/arbeitsbaeume.md (Codex)'
        'Exitcodes: 0 OK, 1 FEHLER, 10 KONFLIKT, 11 ROT, 12 BLOCKIERT, 13 TEILZUSTAND, 14 NICHTS'
    ) | ForEach-Object { Write-Host $_ }
}

function Invoke-Wt {
    $cmd = if ($Befehl) { $Befehl.Trim().ToLowerInvariant() } else { 'help' }
    if ($cmd -in @('help', 'hilfe', '-h', '--help', '-?', '/?')) {
        Show-Hilfe
        Stop-Wt 0 'OK' 'Hilfe'
    }
    if ($cmd -notin @('start', 'sync', 'integrate', 'commit', 'finish', 'status')) {
        Show-Hilfe
        Stop-Wt 1 'FEHLER' "unbekannter Befehl '$Befehl'"
    }
    $rest = @($Dateien | Where-Object { $null -ne $_ -and $_ -ne '' })
    if ($cmd -ne 'commit' -and $rest.Count) {
        Stop-Wt 1 'FEHLER' ("unerwartete Argumente: {0}" -f ($rest -join ' '))
    }
    $ctx = Get-Kontext
    # ungültige Konfiguration in HEAD: status (Standardwerte, WARNUNG) und der Commit genau dieser Datei laufen
    # weiter (Invoke-CmdCommit prüft den Rest), alle anderen Befehle enden mit 1
    if ($ctx.KonfigFehler -and $cmd -notin @('status', 'commit')) {
        Stop-Wt 1 'FEHLER' "$($ctx.KonfigFehler) (Projektwerte aus HEAD nicht verwendbar; erlaubt sind status und wt commit $($script:KonfigRel) im Hauptcheckout)"
    }
    switch ($cmd) {
        'start' { Invoke-CmdStart $ctx }
        'sync' { Invoke-CmdSync $ctx }
        'integrate' { Invoke-CmdIntegrate $ctx }
        'commit' { Invoke-CmdCommit $ctx }
        'finish' { Invoke-CmdFinish $ctx }
        'status' { Invoke-CmdStatus $ctx }
    }
}

# ---------------------------------------------------------------- Einstieg

function Write-WtZeile([string]$Zeile) {
    # direkt auf stdout: -InformationAction Ignore o. Ä. darf die Schlusszeile nicht unterdrücken
    [Console]::Out.WriteLine($Zeile.TrimEnd())
    [Console]::Out.Flush()
}

$script:ExitCode = 1
$alteKodierung = $null
try {
    $alteKodierung = [Console]::OutputEncoding
    [Console]::OutputEncoding = $script:Utf8
} catch {
    $alteKodierung = $null
}
try {
    Invoke-Wt
    Stop-Wt 1 'FEHLER' 'Befehl ohne Ergebnis beendet'
} catch [WtExit] {
    $x = $_.Exception
    $details = ($x.Message -replace '\s*\r?\n\s*', ' ').Trim()
    Write-WtZeile ("WT: {0} {1}" -f $x.Status, $details)
    $script:ExitCode = $x.Code
} catch {
    $fehler = $_
    $meldung = ($fehler.Exception.Message -replace '\s*\r?\n\s*', ' ').Trim()
    Write-Host "Unerwarteter Fehler: $meldung"
    if ($fehler.InvocationInfo -and $fehler.InvocationInfo.ScriptLineNumber) {
        Write-Host "  bei Zeile $($fehler.InvocationInfo.ScriptLineNumber): $($fehler.InvocationInfo.Line.Trim())"
    }
    Write-WtZeile "WT: FEHLER unerwarteter Fehler: $meldung"
    $script:ExitCode = 1
} finally {
    if ($null -ne $alteKodierung) {
        try { [Console]::OutputEncoding = $alteKodierung } catch { }
    }
}
exit $script:ExitCode
