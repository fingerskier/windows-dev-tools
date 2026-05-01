<#
This script helps remove build artifacts and dependency caches from your development projects, reclaiming disk space.  It removes these common artifact types:

  - Node:    node_modules (sibling package.json required)
  - Next.js: .next        (sibling next.config.{js,mjs,ts} required)
  - Python:  .venv, venv, __pycache__, *.egg-info, .eggs, build, dist
  - PHP:     vendor       (sibling composer.json required)
  - Rust:    target       (sibling Cargo.toml required)
  - Android: build, .gradle, .cxx (sibling build.gradle[.kts] / CMakeLists.txt)
  - Flutter: build, .dart_tool (sibling pubspec.yaml required)

# Dry-run scan of a project
clean_dev_artifacts.ps1 C:\dev\customer\project

# Dry-run scan of all your dev work
clean_dev_artifacts.ps1 C:\dev

# Interactive cleanup (prompts per artifact)
clean_dev_artifacts.ps1 C:\dev\customer\project -Delete

# Nuke everything found, no prompts
clean_dev_artifacts.ps1 C:\dev\customer\project -Delete -Force

# Reclaim disk across all projects, unattended
clean_dev_artifacts.ps1 C:\dev -Delete -Force

.SYNOPSIS
    Scan a directory tree for build artifacts and dependency caches, optionally deleting them.

.DESCRIPTION
    Recursively walks $RootDirectory and flags well-known dev artifact directories:
      - Node:    node_modules (sibling package.json required)
      - Next.js: .next        (sibling next.config.{js,mjs,ts} required)
      - Python:  .venv, venv, __pycache__, *.egg-info, .eggs, build, dist
      - PHP:     vendor       (sibling composer.json required)
      - Rust:    target       (sibling Cargo.toml required)
      - Android: build, .gradle, .cxx (sibling build.gradle[.kts] / CMakeLists.txt)
      - Flutter: build, .dart_tool (sibling pubspec.yaml required)

    Flagged directories are not descended into, so nested artifacts are not double-counted.
    Sizes are reported and totaled. Refuses to run against drive roots or system paths.

.PARAMETER RootDirectory
    Directory to scan. Required. Must exist. Drive roots and system paths are blocked.

.PARAMETER Delete
    Without this switch the script runs in DRY-RUN mode: scan + report only, nothing removed.
    With this switch the script prompts Y/N for each artifact before deleting.

.PARAMETER Force
    Only meaningful with -Delete. Skips the per-artifact prompt and deletes everything found.
    Use with care.

.EXAMPLE
    # Dry run -- list artifacts and total size, delete nothing
    .\clean_dev_artifacts.ps1 C:\dev\myproject

.EXAMPLE
    # Interactive delete -- prompt for each artifact
    .\clean_dev_artifacts.ps1 C:\dev\myproject -Delete

.EXAMPLE
    # Unattended delete -- no prompts
    .\clean_dev_artifacts.ps1 C:\dev\myproject -Delete -Force

.NOTES
    Exit codes: 0 = success / dry-run, 1 = invalid path, blocked path, or delete errors.
#>


param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$RootDirectory,

    [switch]$Delete,
    [switch]$Force
)

# --- Validate root directory ---
if (-not (Test-Path $RootDirectory -PathType Container)) {
    Write-Host "ERROR: Directory '$RootDirectory' does not exist." -ForegroundColor Red
    exit 1
}

$resolved = (Resolve-Path $RootDirectory).Path.TrimEnd('\')

# --- Block dangerous root paths ---
$blockedPaths = @(
    'C:', 'D:', 'E:', 'F:',
    'C:\Windows', 'C:\Users',
    'C:\Program Files', 'C:\Program Files (x86)'
)

if ($blockedPaths -contains $resolved) {
    Write-Host "ERROR: Refusing to run against system/root path '$resolved'." -ForegroundColor Red
    Write-Host "       Please provide a more specific project directory." -ForegroundColor Red
    exit 1
}

# --- Collect targets ---
$targets = [System.Collections.ArrayList]::new()

function Get-DirSize {
    param([string]$Path)
    $size = 0
    Get-ChildItem -Path $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
        ForEach-Object { $size += $_.Length }
    return $size
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N1} KB' -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Find-Artifacts {
    param([string]$Path)

    $children = Get-ChildItem -Path $Path -Directory -Force -ErrorAction SilentlyContinue
    if (-not $children) { return }

    foreach ($dir in $children) {
        $name = $dir.Name
        $full = $dir.FullName
        $parent = $dir.Parent.FullName

        # .venv / venv: flag whole virtual environment, don't descend
        if ($name -eq '.venv' -or $name -eq 'venv') {
            if (Test-Path (Join-Path $full 'pyvenv.cfg')) {
                $null = $targets.Add([PSCustomObject]@{
                    Path = $full
                    Type = 'Python'
                    Label = $name
                })
            }
            continue  # never descend into venvs
        }

        # node_modules: must have sibling package.json, skip nested
        if ($name -eq 'node_modules') {
            if (Test-Path (Join-Path $parent 'package.json')) {
                $null = $targets.Add([PSCustomObject]@{
                    Path = $full
                    Type = 'Node'
                    Label = 'node_modules'
                })
            }
            continue  # never descend into node_modules
        }

        # .next: Next.js build output
        if ($name -eq '.next') {
            if ((Test-Path (Join-Path $parent 'next.config.js')) -or
                (Test-Path (Join-Path $parent 'next.config.mjs')) -or
                (Test-Path (Join-Path $parent 'next.config.ts'))) {
                $null = $targets.Add([PSCustomObject]@{
                    Path = $full
                    Type = 'Next.js'
                    Label = '.next'
                })
            }
            continue  # never descend into .next
        }

        # __pycache__: flag unconditionally
        if ($name -eq '__pycache__') {
            $null = $targets.Add([PSCustomObject]@{
                Path = $full
                Type = 'Python'
                Label = '__pycache__'
            })
            continue
        }

        # *.egg-info: flag unconditionally
        if ($name -like '*.egg-info') {
            $null = $targets.Add([PSCustomObject]@{
                Path = $full
                Type = 'Python'
                Label = 'egg-info'
            })
            continue
        }

        # .eggs: flag unconditionally
        if ($name -eq '.eggs') {
            $null = $targets.Add([PSCustomObject]@{
                Path = $full
                Type = 'Python'
                Label = '.eggs'
            })
            continue
        }

        # build: Python, Android, or Flutter
        if ($name -eq 'build') {
            if ((Test-Path (Join-Path $parent 'setup.py')) -or
                (Test-Path (Join-Path $parent 'pyproject.toml'))) {
                $null = $targets.Add([PSCustomObject]@{
                    Path = $full
                    Type = 'Python'
                    Label = 'build'
                })
                continue
            }
            if ((Test-Path (Join-Path $parent 'build.gradle')) -or
                (Test-Path (Join-Path $parent 'build.gradle.kts'))) {
                $null = $targets.Add([PSCustomObject]@{
                    Path = $full
                    Type = 'Android'
                    Label = 'build'
                })
                continue
            }
            if (Test-Path (Join-Path $parent 'pubspec.yaml')) {
                $null = $targets.Add([PSCustomObject]@{
                    Path = $full
                    Type = 'Flutter'
                    Label = 'build'
                })
                continue
            }
        }

        # dist: only with sibling setup.py or pyproject.toml
        if ($name -eq 'dist') {
            if ((Test-Path (Join-Path $parent 'setup.py')) -or
                (Test-Path (Join-Path $parent 'pyproject.toml'))) {
                $null = $targets.Add([PSCustomObject]@{
                    Path = $full
                    Type = 'Python'
                    Label = 'dist'
                })
                continue
            }
        }

        # vendor: PHP Composer dependencies
        if ($name -eq 'vendor') {
            if (Test-Path (Join-Path $parent 'composer.json')) {
                $null = $targets.Add([PSCustomObject]@{
                    Path = $full
                    Type = 'PHP'
                    Label = 'vendor'
                })
            }
            continue  # never descend into vendor
        }

        # target: Rust build output
        if ($name -eq 'target') {
            if (Test-Path (Join-Path $parent 'Cargo.toml')) {
                $null = $targets.Add([PSCustomObject]@{
                    Path = $full
                    Type = 'Rust'
                    Label = 'target'
                })
            }
            continue  # never descend into target
        }

        # .gradle: Android build cache
        if ($name -eq '.gradle') {
            if ((Test-Path (Join-Path $parent 'build.gradle')) -or
                (Test-Path (Join-Path $parent 'build.gradle.kts'))) {
                $null = $targets.Add([PSCustomObject]@{
                    Path = $full
                    Type = 'Android'
                    Label = '.gradle'
                })
            }
            continue  # never descend into .gradle
        }

        # .cxx: Android NDK native build cache
        if ($name -eq '.cxx') {
            if ((Test-Path (Join-Path $parent 'CMakeLists.txt')) -or
                (Test-Path (Join-Path $parent 'build.gradle'))) {
                $null = $targets.Add([PSCustomObject]@{
                    Path = $full
                    Type = 'Android'
                    Label = '.cxx'
                })
            }
            continue  # never descend into .cxx
        }

        # .dart_tool: Flutter tool cache
        if ($name -eq '.dart_tool') {
            if (Test-Path (Join-Path $parent 'pubspec.yaml')) {
                $null = $targets.Add([PSCustomObject]@{
                    Path = $full
                    Type = 'Flutter'
                    Label = '.dart_tool'
                })
            }
            continue  # never descend into .dart_tool
        }

        # Recurse into everything else
        Find-Artifacts -Path $full
    }
}

Write-Host "Scanning '$resolved' for dev artifacts..." -ForegroundColor Cyan
Write-Host ""

Find-Artifacts -Path $resolved

if ($targets.Count -eq 0) {
    Write-Host "No dev artifacts found." -ForegroundColor Green
    exit 0
}

# --- Calculate sizes and display ---
$totalSize = [long]0

Write-Host "Found $($targets.Count) artifact(s):" -ForegroundColor Yellow
Write-Host ""

for ($i = 0; $i -lt $targets.Count; $i++) {
    $t = $targets[$i]
    $size = Get-DirSize -Path $t.Path
    $t | Add-Member -NotePropertyName 'Size' -NotePropertyValue $size
    $totalSize += $size

    $typeColor = switch ($t.Type) {
        'Node'    { 'Cyan' }
        'Next.js' { 'White' }
        'PHP'     { 'DarkYellow' }
        'Rust'    { 'Red' }
        'Android' { 'Green' }
        'Flutter' { 'Blue' }
        default   { 'Magenta' }
    }
    $idx = ($i + 1).ToString().PadLeft(3)
    Write-Host "  $idx. " -NoNewline
    Write-Host "[$($t.Type)]" -ForegroundColor $typeColor -NoNewline
    Write-Host " $($t.Label) " -NoNewline -ForegroundColor DarkGray
    Write-Host (Format-Size $size) -NoNewline -ForegroundColor Yellow
    Write-Host ""
    Write-Host "       $($t.Path)" -ForegroundColor Gray
}

Write-Host ""
Write-Host "Total: $($targets.Count) artifact(s), $(Format-Size $totalSize)" -ForegroundColor Yellow

# --- Dry-run mode ---
if (-not $Delete) {
    Write-Host ""
    Write-Host "Dry run -- use -Delete to remove, or -Delete -Force to skip prompts." -ForegroundColor DarkYellow
    exit 0
}

# --- Delete mode ---
Write-Host ""
$deleted = 0
$skipped = 0
$errors = 0

foreach ($t in $targets) {
    $confirm = $true

    if (-not $Force) {
        $answer = Read-Host "Delete '$($t.Path)'? (Y/N)"
        if ($answer -notmatch '^[Yy]') {
            Write-Host "  Skipped." -ForegroundColor DarkGray
            $skipped++
            continue
        }
    }

    try {
        Remove-Item -Path $t.Path -Recurse -Force -ErrorAction Stop
        Write-Host "  Deleted $($t.Path)" -ForegroundColor Green
        $deleted++
    }
    catch {
        Write-Host "  ERROR: Failed to delete $($t.Path) - $_" -ForegroundColor Red
        $errors++
    }
}

Write-Host ""
Write-Host "Deleted $deleted of $($targets.Count) artifact(s)." -ForegroundColor Cyan
if ($skipped -gt 0) { Write-Host "Skipped $skipped." -ForegroundColor DarkGray }
if ($errors -gt 0) {
    Write-Host "Errors: $errors." -ForegroundColor Red
    exit 1
}
