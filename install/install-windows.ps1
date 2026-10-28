<#
.SYNOPSIS
  Installs the Nysonian db-write-guard into Codex CLI, Gemini CLI and Antigravity CLI (agy) on Windows.

.DESCRIPTION
  Copies the guard script to one folder, writes a guard.cmd launcher that runs it with Git Bash,
  and registers it as a pre-tool hook in each tool. Claude Code is not handled here: it gets the
  guard as a plugin through the claude.ai admin console (see README).

  -Scope User     (default) Installs for the current user only. No admin rights needed.
                  The user can remove it. Codex asks the user to trust the hook once in /hooks.
  -Scope Machine  Run as administrator. Codex and Gemini CLI get it through their system-wide
                  policy files, which users cannot override. agy has no system-wide location,
                  so agy is still set up for the current user only.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install\install-windows.ps1
  powershell -ExecutionPolicy Bypass -File install\install-windows.ps1 -Scope Machine
  powershell -ExecutionPolicy Bypass -File install\install-windows.ps1 -Uninstall
#>
param(
  [ValidateSet('User', 'Machine')] [string]$Scope = 'User',
  [ValidateSet('codex', 'gemini', 'agy')] [string[]]$Tools = @('codex', 'gemini', 'agy'),
  [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$Marker = 'nysonian-db-write-guard'
$RepoRoot = Split-Path $PSScriptRoot -Parent
$GuardSource = Join-Path $RepoRoot 'plugins\db-write-guard\scripts\db-write-guard.sh'

if ($Scope -eq 'Machine') {
  $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $isAdmin) { throw 'Scope Machine needs an administrator PowerShell. Right-click PowerShell, choose Run as administrator, and run this again.' }
  $InstallDir = Join-Path $env:ProgramData 'NysonianGuard'
} else {
  $InstallDir = Join-Path $env:USERPROFILE '.nysonian-guard'
}
$Launcher = Join-Path $InstallDir 'guard.cmd'

# Some agents (agy) mangle quoted paths when they run a hook through cmd.exe, so the hook command
# uses a path without spaces: the plain path, or the 8.3 short path when the folder name has spaces.
function Get-LauncherPath {
  if ($Launcher -notmatch ' ') { return $Launcher }
  if (Test-Path $Launcher) {
    $short = (New-Object -ComObject Scripting.FileSystemObject).GetFile($Launcher).ShortPath
    if ($short -notmatch ' ') { return $short }
  }
  Write-Warning "  $Launcher has spaces and no short name; agy may fail to run it. Install from a folder without spaces."
  return "`"$Launcher`""
}

function Get-HookCommand([string]$format) { return "$(Get-LauncherPath) $format" }

function Read-JsonFile([string]$path) {
  if (Test-Path $path) {
    $raw = [IO.File]::ReadAllText($path)
    if ($raw.Trim()) { return ($raw | ConvertFrom-Json) }
  }
  return [pscustomobject]@{}
}

function Write-JsonFile([string]$path, $obj) {
  $dir = Split-Path $path -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if ((Test-Path $path) -and -not (Test-Path "$path.$Marker.bak")) { Copy-Item $path "$path.$Marker.bak" }
  $json = $obj | ConvertTo-Json -Depth 50
  [IO.File]::WriteAllText($path, $json, (New-Object Text.UTF8Encoding $false))
}

function Get-Prop($obj, [string]$name, $default) {
  if (-not ($obj.PSObject.Properties.Name -contains $name)) {
    $obj | Add-Member -NotePropertyName $name -NotePropertyValue $default
  }
  return $obj.$name
}

function Test-OurEntry($entry) {
  return (($entry | ConvertTo-Json -Depth 20 -Compress) -match 'nysonian-guard|NysonianGuard')
}

# Removes our entries from hooks.<eventName>, then adds $newEntry unless it is $null.
function Set-HookEntry($hooksObj, [string]$eventName, $newEntry) {
  $existing = @()
  if ($hooksObj.PSObject.Properties.Name -contains $eventName) {
    $existing = @($hooksObj.$eventName | Where-Object { -not (Test-OurEntry $_) })
  }
  if ($null -ne $newEntry) { $existing += $newEntry }
  if ($hooksObj.PSObject.Properties.Name -contains $eventName) { $hooksObj.PSObject.Properties.Remove($eventName) }
  if ($existing.Count -gt 0) { $hooksObj | Add-Member -NotePropertyName $eventName -NotePropertyValue ([object[]]$existing) }
}

function Find-GitBash {
  $candidates = @(
    (Join-Path $env:ProgramFiles 'Git\bin\bash.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Git\bin\bash.exe'),
    (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe')
  )
  $git = Get-Command git -ErrorAction SilentlyContinue
  if ($git) { $candidates += (Join-Path (Split-Path (Split-Path $git.Source -Parent) -Parent) 'bin\bash.exe') }
  foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
  throw 'Git Bash was not found. Install Git for Windows (https://git-scm.com/download/win) and run this again.'
}

# ---------- Guard files ----------
function Install-GuardFiles {
  if (-not (Test-Path $GuardSource)) { throw "Guard script not found at $GuardSource. Run this from a checkout of the repo." }
  $bash = Find-GitBash
  New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
  Copy-Item $GuardSource (Join-Path $InstallDir 'db-write-guard.sh') -Force
  $cmd = "@echo off`r`n`"$bash`" `"%~dp0db-write-guard.sh`" --format %1`r`n"
  [IO.File]::WriteAllText($Launcher, $cmd, (New-Object Text.ASCIIEncoding))
  Write-Host "  Guard installed in $InstallDir (using $bash)"
}

# ---------- Codex ----------
function Set-CodexUser([bool]$remove) {
  $path = Join-Path $env:USERPROFILE '.codex\hooks.json'
  if ($remove -and -not (Test-Path $path)) { return }
  $cfg = Read-JsonFile $path
  $hooks = Get-Prop $cfg 'hooks' ([pscustomobject]@{})
  $entry = $null
  if (-not $remove) {
    $entry = [pscustomobject]@{
      matcher = '.*'
      hooks   = @([pscustomobject]@{ type = 'command'; command = (Get-HookCommand 'codex'); statusMessage = 'Checking company AI policy'; timeout = 10 })
    }
  }
  Set-HookEntry $hooks 'PreToolUse' $entry
  Write-JsonFile $path $cfg
  if ($remove) { Write-Host "  Codex: removed from $path" }
  else { Write-Host "  Codex: added to $path. Each user must approve it once: open Codex, run /hooks, and trust the $Marker hook." }
}

function Set-CodexMachine([bool]$remove) {
  $path = Join-Path $env:ProgramData 'OpenAI\Codex\requirements.toml'
  $begin = "# >>> $Marker"
  $end = "# <<< $Marker"
  $content = ''
  if (Test-Path $path) { $content = [IO.File]::ReadAllText($path) }
  $content = [regex]::Replace($content, "(?s)\r?\n?$([regex]::Escape($begin)).*?$([regex]::Escape($end))\r?\n?", "`r`n")
  if (-not $remove) {
    if ($content -match '(?m)^\s*\[(features|hooks)\]') {
      throw "$path already has a [features] or [hooks] section. Ask IT to merge the Nysonian hook block into it by hand."
    }
    $dir = $InstallDir
    $block = @"
$begin
[features]
hooks = true

[hooks]
windows_managed_dir = '$dir'

[[hooks.PreToolUse]]
matcher = ".*"

[[hooks.PreToolUse.hooks]]
type = "command"
command = '$(Get-HookCommand 'codex')'
command_windows = '$(Get-HookCommand 'codex')'
statusMessage = "Checking company AI policy"
timeout = 10
$end
"@
    $content = $content.TrimEnd() + "`r`n`r`n" + $block + "`r`n"
  }
  New-Item -ItemType Directory -Force -Path (Split-Path $path -Parent) | Out-Null
  if ((Test-Path $path) -and -not (Test-Path "$path.$Marker.bak")) { Copy-Item $path "$path.$Marker.bak" }
  [IO.File]::WriteAllText($path, $content.TrimStart(), (New-Object Text.UTF8Encoding $false))
  if ($remove) { Write-Host "  Codex: removed from $path" } else { Write-Host "  Codex: added to $path (managed, users cannot turn it off)" }
}

# ---------- Gemini CLI ----------
function Set-Gemini([bool]$remove) {
  if ($Scope -eq 'Machine') { $path = Join-Path $env:ProgramData 'gemini-cli\settings.json' }
  else { $path = Join-Path $env:USERPROFILE '.gemini\settings.json' }
  if ($remove -and -not (Test-Path $path)) { return }
  $cfg = Read-JsonFile $path
  $hooks = Get-Prop $cfg 'hooks' ([pscustomobject]@{})
  $entry = $null
  if (-not $remove) {
    $entry = [pscustomobject]@{
      matcher = '.*'
      hooks   = @([pscustomobject]@{ name = $Marker; type = 'command'; command = (Get-HookCommand 'gemini'); timeout = 10000 })
    }
  }
  Set-HookEntry $hooks 'BeforeTool' $entry
  Write-JsonFile $path $cfg
  if ($remove) { Write-Host "  Gemini CLI: removed from $path" } else { Write-Host "  Gemini CLI: added to $path" }
}

# ---------- Antigravity CLI (agy) ----------
function Set-Agy([bool]$remove) {
  $path = Join-Path $env:USERPROFILE '.gemini\config\hooks.json'
  if ($remove -and -not (Test-Path $path)) { return }
  $cfg = Read-JsonFile $path
  if ($cfg.PSObject.Properties.Name -contains $Marker) { $cfg.PSObject.Properties.Remove($Marker) }
  if (-not $remove) {
    $group = [pscustomobject]@{
      enabled    = $true
      PreToolUse = @([pscustomobject]@{
          matcher = '.*'
          hooks   = @([pscustomobject]@{ type = 'command'; command = (Get-HookCommand 'agy'); timeout = 10 })
        })
    }
    $cfg | Add-Member -NotePropertyName $Marker -NotePropertyValue $group
  }
  Write-JsonFile $path $cfg
  if ($remove) { Write-Host "  agy: removed from $path" }
  else {
    $note = ''
    if ($Scope -eq 'Machine') { $note = " (agy has no system-wide location, so this covers user $env:USERNAME only)" }
    Write-Host "  agy: added to $path$note"
  }
}

# ---------- Run ----------
$remove = [bool]$Uninstall
Write-Host ("{0} db-write-guard ({1} scope)" -f ($(if ($remove) { 'Removing' } else { 'Installing' }), $Scope))
if (-not $remove) { Install-GuardFiles }

foreach ($t in $Tools) {
  try {
    switch ($t) {
      'codex' { if ($Scope -eq 'Machine') { Set-CodexMachine $remove } else { Set-CodexUser $remove } }
      'gemini' { Set-Gemini $remove }
      'agy' { Set-Agy $remove }
    }
  } catch {
    Write-Warning "  ${t}: $($_.Exception.Message)"
  }
}

if ($remove -and (Test-Path $InstallDir)) {
  Remove-Item -Recurse -Force $InstallDir
  Write-Host "  Removed $InstallDir"
}
Write-Host 'Done. Restart any open Codex, Gemini CLI or agy sessions.'
