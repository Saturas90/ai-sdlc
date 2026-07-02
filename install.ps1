# install.ps1 — verlinkt (oder kopiert) Skills, Sub-Agenten und Wissensbasis nach ~/.claude
#
#   Standard:  Symlinks (Repo-Änderungen wirken sofort). Braucht Admin ODER Windows-Entwicklermodus.
#   Fallback:  bei fehlenden Rechten wird automatisch kopiert.
#   Erzwungen: .\install.ps1 -Copy   (immer kopieren)
#
[CmdletBinding()]
param([switch]$Copy)

$ErrorActionPreference = 'Stop'
$repo   = Split-Path -Parent $MyInvocation.MyCommand.Path
$claude = Join-Path $HOME '.claude'

New-Item -ItemType Directory -Force -Path (Join-Path $claude 'skills') | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $claude 'agents') | Out-Null

function Remove-Target {
    # Entfernt Datei/Ordner ODER Symlink sicher. Bei einem Verzeichnis-Symlink NUR den Link
    # loeschen, niemals mit -Recurse in das Ziel absteigen (sonst drohte Datenverlust im Quell-Repo).
    param([string]$Path)
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
    param([string]$Source, [string]$Target, [bool]$IsDir)
    Remove-Target $Target
    if (-not $Copy) {
        try {
            New-Item -ItemType SymbolicLink -Path $Target -Target $Source -ErrorAction Stop | Out-Null
            Write-Host "  link  $Target"
            return
        } catch {
            Write-Warning "  Symlink fehlgeschlagen -> kopiere. (Admin oder Windows-Entwicklermodus aktiviert Symlinks.)"
        }
    }
    if ($IsDir) { Copy-Item $Source $Target -Recurse -Force } else { Copy-Item $Source $Target -Force }
    Write-Host "  copy  $Target"
}

Write-Host "Skills ->  $claude\skills"
foreach ($d in Get-ChildItem (Join-Path $repo '.claude\skills') -Directory) {
    Install-Item $d.FullName (Join-Path $claude "skills\$($d.Name)") $true
}
Write-Host "Agenten ->  $claude\agents"
foreach ($f in Get-ChildItem (Join-Path $repo '.claude\agents') -File) {
    Install-Item $f.FullName (Join-Path $claude "agents\$($f.Name)") $false
}
Write-Host "Wissensbasis ->  $claude\ai-sdlc"
Install-Item (Join-Path $repo 'share') (Join-Path $claude 'ai-sdlc') $true

Write-Host "`nFertig. Skills und Sub-Agenten sind jetzt global unter ~/.claude verfuegbar."
Write-Host "In einem beliebigen Projekt: /naechster-schritt oder /projektplan aufrufen."
