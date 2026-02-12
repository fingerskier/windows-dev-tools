param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$baseDirectory
)

$originalDir = Get-Location
Clear-Host

$excludeDirs = @('node_modules', '.git', 'vendor', 'dist', 'build', '__pycache__', '.venv', 'venv', 'bower_components', '.next', '.nuxt')

function Find-GitRepos {
    param([string]$Path)

    if (Test-Path "$Path\.git") {
        Write-Output $Path
        return  # don't recurse into a git repo's subdirectories
    }

    Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue |
        Where-Object { $excludeDirs -notcontains $_.Name } |
        ForEach-Object { Find-GitRepos -Path $_.FullName }
}

try {
    $repos = Find-GitRepos -Path $baseDirectory

    foreach ($repoPath in $repos) {
        Set-Location $repoPath

        git -c fetch.timeout=10 fetch --quiet 2>$null

        $branch = git branch --show-current
        $status = git status --porcelain

        if (![string]::IsNullOrWhiteSpace($status)) {
            Write-Host "[CHANGES] $repoPath Has uncommitted changes on branch $branch" -ForegroundColor Red
        }

        $behind = git status -sb | Select-String "behind"
        if ($behind) {
            Write-Host "[BEHIND] $repoPath Repository is behind remote" -ForegroundColor Yellow
        }

        if (![string]::IsNullOrWhiteSpace($status) -or $behind) {
            Write-Host ""
        }
    }
}
finally {
    Set-Location $originalDir
}
