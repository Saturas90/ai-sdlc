# Installiert Claude-Code- und Codex-Workflow-Dateien aus diesem Repository.
# Standard: Symlinks, bei fehlenden Rechten Kopien. -Copy erzwingt Kopien.
# -ClaudeHome und -CodexHome erlauben eine isolierte Probeinstallation.
[CmdletBinding()]
param(
    [switch]$Copy,
    [string]$ClaudeHome = (Join-Path $HOME '.claude'),
    [string]$CodexHome = (Join-Path $HOME '.codex')
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $MyInvocation.MyCommand.Path
$claudeRoot = [IO.Path]::GetFullPath($ClaudeHome)
$codexRoot = [IO.Path]::GetFullPath($CodexHome)
$codexBackupRoot = Join-Path $codexRoot ('ai-sdlc-backups\' + [guid]::NewGuid().ToString('N'))

function Assert-TargetWithinRoot {
    param([string]$Path, [string]$Root)
    $absolute = [IO.Path]::GetFullPath($Path)
    $prefix = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $absolute.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Ziel liegt außerhalb des Installationsverzeichnisses: $absolute"
    }
}

function Remove-Target {
    param([string]$Path, [string]$Root)
    Assert-TargetWithinRoot $Path $Root
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return }
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        if ($item.PSIsContainer) { [System.IO.Directory]::Delete($Path, $false) }
        else { [System.IO.File]::Delete($Path) }
    } else {
        Remove-Item -LiteralPath $Path -Recurse -Force
    }
}

function Install-Item {
    param([string]$Source, [string]$Target, [bool]$IsDir, [string]$Root)
    Remove-Target $Target $Root
    if (-not $Copy) {
        try {
            New-Item -ItemType SymbolicLink -Path $Target -Target $Source -ErrorAction Stop | Out-Null
            Write-Host "  link  $Target"
            return
        } catch {
            Write-Warning "  Symlink fehlgeschlagen -> kopiere. (Admin oder Windows-Entwicklermodus aktiviert Symlinks.)"
        }
    }
    if ($IsDir) { Copy-Item -LiteralPath $Source -Destination $Target -Recurse -Force }
    else { Copy-Item -LiteralPath $Source -Destination $Target -Force }
    Write-Host "  copy  $Target"
}

function Backup-CodexFile {
    param([string]$Target)
    Assert-TargetWithinRoot $Target $codexRoot
    if (-not (Test-Path -LiteralPath $Target)) { return }
    $relative = [IO.Path]::GetRelativePath($codexRoot, [IO.Path]::GetFullPath($Target))
    $backup = Join-Path $codexBackupRoot $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $backup) | Out-Null
    Copy-Item -LiteralPath $Target -Destination $backup -Force
    Write-Host "  backup  $backup"
}

function Install-CodexFile {
    param([string]$Source, [string]$Target)
    Assert-TargetWithinRoot $Target $codexRoot
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Target) | Out-Null
    if (Test-Path -LiteralPath $Target) {
        $existing = Get-Item -LiteralPath $Target -Force
        if ((Get-FileHash -LiteralPath $Source).Hash -eq (Get-FileHash -LiteralPath $Target).Hash) {
            if ($Copy -and (($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
                Remove-Target $Target $codexRoot
            } else { return }
        } else {
            Backup-CodexFile $Target
            Remove-Target $Target $codexRoot
        }
    }
    Install-Item $Source $Target $false $codexRoot
}

function Set-ConfigValue {
    param([string]$Block, [string]$Key, [string]$Value)
    $pattern = '(?m)^[ \t]*' + [regex]::Escape($Key) + '[ \t]*=[^\r\n]*(?=\r?$)'
    $matches = [regex]::Matches($Block, $pattern)
    if ($matches.Count -gt 1) { throw "Doppelter TOML-Schlüssel: $Key" }
    $assignment = $Key + ' = "' + $Value + '"'
    if ($matches.Count -eq 1) { return [regex]::Replace($Block, $pattern, $assignment) }
    return $Block.TrimEnd("`r", "`n") + "`n" + $assignment + "`n"
}

function Get-ConfigValue {
    param([string]$Block, [string]$Key)
    $pattern = '(?m)^[ \t]*' + [regex]::Escape($Key) + '[ \t]*=[ \t]*"([^"]+)"[ \t]*(?=\r?$)'
    $matches = [regex]::Matches($Block, $pattern)
    if ($matches.Count -ne 1) { throw "Erwarteter TOML-Schlüssel fehlt oder ist doppelt: $Key" }
    return $matches[0].Groups[1].Value
}

function Split-ConfigSections {
    param([string]$Content)
    return [regex]::Split($Content, '(?m)(?=^\[[^\]\r\n]+\][ \t]*\r?$)')
}

function Install-CodexConfig {
    $defaults = Get-Content -LiteralPath (Join-Path $repo 'codex\config.defaults.toml') -Raw
    $defaultSections = @(Split-ConfigSections $defaults)
    if ($defaultSections.Count -ne 2 -or $defaultSections[1] -notmatch '^\[agents\]') {
        throw 'Ungültige codex/config.defaults.toml'
    }
    $values = @{
        model = Get-ConfigValue $defaultSections[0] 'model'
        model_reasoning_effort = Get-ConfigValue $defaultSections[0] 'model_reasoning_effort'
        default_subagent_model = Get-ConfigValue $defaultSections[1] 'default_subagent_model'
        default_subagent_reasoning_effort = Get-ConfigValue $defaultSections[1] 'default_subagent_reasoning_effort'
    }
    $target = Join-Path $codexRoot 'config.toml'
    $current = if (Test-Path -LiteralPath $target) { Get-Content -LiteralPath $target -Raw } else { '' }
    $sections = [Collections.Generic.List[string]]::new()
    foreach ($section in (Split-ConfigSections $current)) { $sections.Add($section) }
    $sections[0] = Set-ConfigValue $sections[0] 'model' $values.model
    $sections[0] = Set-ConfigValue $sections[0] 'model_reasoning_effort' $values.model_reasoning_effort
    $agentIndex = -1
    for ($i = 1; $i -lt $sections.Count; $i++) {
        if ($sections[$i] -match '^\[agents\][ \t]*\r?\n') { $agentIndex = $i; break }
    }
    if ($agentIndex -lt 0) {
        $sections.Add("`n[agents]`n")
        $agentIndex = $sections.Count - 1
    }
    $sections[$agentIndex] = Set-ConfigValue $sections[$agentIndex] 'default_subagent_model' $values.default_subagent_model
    $sections[$agentIndex] = Set-ConfigValue $sections[$agentIndex] 'default_subagent_reasoning_effort' $values.default_subagent_reasoning_effort
    $updated = $sections -join ''
    if ($updated -ne $current) {
        Backup-CodexFile $target
        $existing = Get-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        if ($null -ne $existing -and
            ($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Remove-Target $target $codexRoot
        }
        [IO.File]::WriteAllText($target, $updated, [Text.UTF8Encoding]::new($false))
        Write-Host "  update  $target (nur Modell-Standardwerte)"
    }
}

New-Item -ItemType Directory -Force -Path (Join-Path $claudeRoot 'skills'), (Join-Path $claudeRoot 'agents'), $codexRoot | Out-Null

Write-Host "Claude-Skills ->  $claudeRoot\skills"
foreach ($directory in Get-ChildItem -LiteralPath (Join-Path $repo '.claude\skills') -Directory) {
    Install-Item $directory.FullName (Join-Path $claudeRoot "skills\$($directory.Name)") $true $claudeRoot
}
Write-Host "Claude-Agenten ->  $claudeRoot\agents"
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repo '.claude\agents') -File) {
    Install-Item $file.FullName (Join-Path $claudeRoot "agents\$($file.Name)") $false $claudeRoot
}
Write-Host "Claude-Wissensbasis ->  $claudeRoot\ai-sdlc"
Install-Item (Join-Path $repo 'share') (Join-Path $claudeRoot 'ai-sdlc') $true $claudeRoot

Write-Host "Codex-Regeln ->  $codexRoot"
Install-CodexFile (Join-Path $repo 'codex\AGENTS.md') (Join-Path $codexRoot 'AGENTS.md')
foreach ($file in Get-ChildItem -LiteralPath (Join-Path $repo 'codex\agents') -Filter '*.toml' -File) {
    Install-CodexFile $file.FullName (Join-Path $codexRoot "agents\$($file.Name)")
}
foreach ($directory in Get-ChildItem -LiteralPath (Join-Path $repo 'codex\skills') -Directory) {
    Install-CodexFile (Join-Path $directory.FullName 'SKILL.md') (Join-Path $codexRoot "skills\$($directory.Name)\SKILL.md")
}
Install-CodexConfig

Write-Host "`nFertig. Claude Code und Codex verwenden den installierten SDLC-Workflow."
