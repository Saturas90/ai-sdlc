[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path $repo ('.install-smoke-' + [guid]::NewGuid().ToString('N'))
$repoPrefix = [IO.Path]::GetFullPath($repo).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$testPath = [IO.Path]::GetFullPath($testRoot)
if (-not $testPath.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase) -or
    -not [IO.Path]::GetFileName($testPath).StartsWith('.install-smoke-')) {
    throw 'Unzulässiges Testziel'
}

try {
    $claudeTarget = Join-Path $testPath 'claude'
    $codexTarget = Join-Path $testPath 'codex'
    $reviewTarget = Join-Path $codexTarget 'skills\review'
    New-Item -ItemType Directory -Force -Path $reviewTarget | Out-Null
    $existingConfig = @'
model = "gpt-5.6-sol"
model_reasoning_effort = "high"
personality = "pragmatic"
[agents]
default_subagent_model = "gpt-5.6-terra"
default_subagent_reasoning_effort = "high"
max_concurrent_threads_per_session = 2
[projects.'demo']
trust_level = "trusted"
'@
    [IO.File]::WriteAllText((Join-Path $codexTarget 'config.toml'), ($existingConfig -replace '\r?\n', "`r`n"))
    [IO.File]::WriteAllText((Join-Path $codexTarget 'AGENTS.md'), 'vorherige Nutzerregel')
    [IO.File]::WriteAllText((Join-Path $reviewTarget 'notes.txt'), 'behalten')
    $claudeToolsTarget = Join-Path $claudeTarget 'ai-sdlc\tools'
    New-Item -ItemType Directory -Force -Path (Join-Path $claudeToolsTarget '__pycache__') | Out-Null
    [IO.File]::WriteAllText((Join-Path $claudeToolsTarget 'baseline-eigene.txt'), 'eigene Baseline')
    [IO.File]::WriteAllText((Join-Path $claudeToolsTarget '__pycache__\cache.pyc'), 'cache')
    $claudeSkillTarget = Join-Path $claudeTarget 'skills\review'
    New-Item -ItemType Directory -Force -Path $claudeSkillTarget | Out-Null
    [IO.File]::WriteAllText((Join-Path $claudeSkillTarget 'eigene-notiz.md'), 'eigene Notiz')

    & (Join-Path $repo 'install.ps1') -Copy -ClaudeHome $claudeTarget -CodexHome $codexTarget *> (Join-Path $testPath 'first.log')
    $config = Get-Content -LiteralPath (Join-Path $codexTarget 'config.toml') -Raw
    if ($config -notmatch 'model = "gpt-6-sol"' -or
        $config -notmatch 'personality = "pragmatic"' -or
        $config -notmatch 'trust_level = "trusted"' -or
        [regex]::Matches($config, '(?m)^model[ \t]*=').Count -ne 1 -or
        [regex]::Matches($config, '(?m)^default_subagent_model[ \t]*=').Count -ne 1 -or
        -not (Test-Path -LiteralPath (Join-Path $claudeTarget 'skills\review\SKILL.md')) -or
        -not (Test-Path -LiteralPath (Join-Path $claudeTarget 'agents\reviewer.md')) -or
        -not (Test-Path -LiteralPath (Join-Path $claudeTarget 'agents\reviewer-architektur.md')) -or
        -not (Test-Path -LiteralPath (Join-Path $claudeTarget 'agents\mutations-pruefer.md')) -or
        -not (Test-Path -LiteralPath (Join-Path $claudeTarget 'agents\rechercheur.md')) -or
        -not (Test-Path -LiteralPath (Join-Path $claudeTarget 'ai-sdlc\vorlagen\kontext.md')) -or
        -not (Test-Path -LiteralPath (Join-Path $claudeTarget 'ai-sdlc\konventionen.md')) -or
        -not (Test-Path -LiteralPath (Join-Path $claudeTarget 'ai-sdlc\tools\verbrauch_auswerten.py')) -or
        -not (Test-Path -LiteralPath (Join-Path $codexTarget 'agents\architekt_kritisch.toml')) -or
        -not (Test-Path -LiteralPath (Join-Path $reviewTarget 'notes.txt'))) {
        throw 'Installationsinhalt ist falsch'
    }
    $backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $codexTarget 'ai-sdlc-backups') -Recurse -File)
    if (-not ($backupFiles.Name -contains 'AGENTS.md') -or
        -not ($backupFiles.Name -contains 'config.toml')) {
        throw 'Sicherung vorhandener Codex-Dateien fehlt'
    }
    $claudeBackups = @(Get-ChildItem -LiteralPath (Join-Path $claudeTarget 'ai-sdlc-backups') -Recurse -File -ErrorAction SilentlyContinue)
    $backupPaths = @($claudeBackups.FullName)
    if (-not ($backupPaths -like '*\ai-sdlc-backups\*\ai-sdlc\tools\baseline-eigene.txt') -or
        -not ($backupPaths -like '*\ai-sdlc-backups\*\skills\review\eigene-notiz.md') -or
        ($claudeBackups.Name -contains 'cache.pyc') -or
        (Test-Path -LiteralPath (Join-Path $claudeToolsTarget 'baseline-eigene.txt')) -or
        (Test-Path -LiteralPath (Join-Path $claudeToolsTarget '__pycache__\cache.pyc')) -or
        (Test-Path -LiteralPath (Join-Path $claudeSkillTarget 'eigene-notiz.md'))) {
        throw 'Eigene Dateien im Claude-Installationsverzeichnis wurden nicht korrekt gesichert'
    }

    & (Join-Path $repo 'install.ps1') -Copy -ClaudeHome $claudeTarget -CodexHome $codexTarget *> (Join-Path $testPath 'second.log')
    $after = @(Get-ChildItem -LiteralPath (Join-Path $codexTarget 'ai-sdlc-backups') -Recurse -File)
    $claudeAfter = @(Get-ChildItem -LiteralPath (Join-Path $claudeTarget 'ai-sdlc-backups') -Recurse -File)
    if ($backupFiles.Count -ne $after.Count -or $claudeBackups.Count -ne $claudeAfter.Count) {
        throw 'Zweite Installation ist nicht idempotent'
    }

    # Der Standardlauf darf keine SKILL.md-Dateilinks erzeugen: Codex überspringt sie.
    $defaultClaudeTarget = Join-Path $testPath 'claude-default'
    $defaultCodexTarget = Join-Path $testPath 'codex-default'
    $defaultSkillSource = Join-Path $repo 'codex\skills\implementieren\SKILL.md'
    $defaultSkillTarget = Join-Path $defaultCodexTarget 'skills\implementieren\SKILL.md'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $defaultSkillTarget) | Out-Null
    $seededSkillLink = $false
    try {
        New-Item -ItemType SymbolicLink -Path $defaultSkillTarget -Target $defaultSkillSource -ErrorAction Stop | Out-Null
        $seededSkillLink = $true
    } catch {
        Write-Output 'Dateilink-Migration mangels Symlink-Rechten nicht prüfbar; Standardinstallation wird geprüft.'
    }
    $defaultSkillNotes = Join-Path (Split-Path -Parent $defaultSkillTarget) 'notes.txt'
    [IO.File]::WriteAllText($defaultSkillNotes, 'behalten')
    & (Join-Path $repo 'install.ps1') -ClaudeHome $defaultClaudeTarget -CodexHome $defaultCodexTarget *> (Join-Path $testPath 'default.log')
    foreach ($skill in Get-ChildItem -LiteralPath (Join-Path $repo 'codex\skills') -Directory) {
        $sourceFile = Join-Path $skill.FullName 'SKILL.md'
        $targetFile = Join-Path $defaultCodexTarget "skills\$($skill.Name)\SKILL.md"
        $installedFile = Get-Item -LiteralPath $targetFile -Force
        if (($installedFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            (Get-FileHash -LiteralPath $sourceFile).Hash -ne (Get-FileHash -LiteralPath $targetFile).Hash) {
            throw "Codex-Skill ist keine unveränderte reguläre Datei: $($skill.Name)"
        }
    }
    if ((Get-Content -LiteralPath $defaultSkillNotes -Raw) -ne 'behalten') {
        throw 'Eigene Datei im Codex-Skill-Verzeichnis wurde verändert'
    }
    if ($seededSkillLink -and
        (Get-Item -LiteralPath $defaultSkillTarget -Force).LinkType -eq 'SymbolicLink') {
        throw 'Bestehender SKILL.md-Dateilink wurde nicht migriert'
    }
    $defaultWriteTimes = @{}
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $defaultCodexTarget 'skills') -Recurse -File) {
        $defaultWriteTimes[$file.FullName] = $file.LastWriteTimeUtc
    }
    & (Join-Path $repo 'install.ps1') -ClaudeHome $defaultClaudeTarget -CodexHome $defaultCodexTarget *> (Join-Path $testPath 'default-second.log')
    foreach ($filePath in $defaultWriteTimes.Keys) {
        if ((Get-Item -LiteralPath $filePath).LastWriteTimeUtc -ne $defaultWriteTimes[$filePath]) {
            throw "Zweite Standardinstallation hat eine unveränderte Skill-Datei neu geschrieben: $filePath"
        }
    }
    Write-Output 'Installations-Smoke-Test: OK'
} finally {
    if (Test-Path -LiteralPath $testPath) {
        $resolved = (Resolve-Path -LiteralPath $testPath).Path
        if (-not $resolved.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase) -or
            -not [IO.Path]::GetFileName($resolved).StartsWith('.install-smoke-')) {
            throw 'Testziel vor der Löschung nicht verifiziert'
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
