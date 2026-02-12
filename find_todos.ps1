param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$baseDirectory
)

$excludeDirs = @('node_modules', '.git', 'vendor', 'dist', 'build', '__pycache__', '.venv', 'venv', 'bower_components', '.next', '.nuxt')

function Find-TodoFiles {
    param([string]$Path)

    $todoPath = Join-Path $Path 'TODO.md'
    if (Test-Path $todoPath) {
        Write-Output $todoPath
    }

    Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue |
        Where-Object { $excludeDirs -notcontains $_.Name } |
        ForEach-Object { Find-TodoFiles -Path $_.FullName }
}

$files = Find-TodoFiles -Path $baseDirectory

if (-not $files) {
    Write-Host "No TODO.md files found under $baseDirectory" -ForegroundColor Yellow
    return
}

foreach ($file in $files) {
    Write-Host "=== $file ===" -ForegroundColor Cyan
    Get-Content $file
    Write-Host ""
}
