<#
.SYNOPSIS
    push-clean.ps1: Wipe Git History & Force Push a Single Clean Commit
    Target OS: Windows (PowerShell 5.1 & PowerShell Core 7+)

.EXAMPLE
    .\config\push-clean\push-clean.ps1 "Release: $(Get-Date -Format 'yyyy-MM-dd')"
#>

param(
    [string]$CommitMessage = "Clean release: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    [string]$TargetBranch = "main",
    [string]$Remote = "origin"
)

$ErrorActionPreference = "Stop"

# Navigate to git root
$repoRoot = git rev-parse --show-toplevel 2>$null
if ($LASTEXITCODE -eq 0 -and $repoRoot) {
    Set-Location $repoRoot
}

Write-Host "🧹 Preparing clean, zero-history push to $Remote/$TargetBranch..." -ForegroundColor Cyan

# Safety check for config.yml placeholders
if (Test-Path "config.yml") {
    $content = Get-Content "config.yml" -Raw
    if ($content -match "AAAA|your_access_key") {
        Write-Host "✅ Detected sample placeholders in config.yml." -ForegroundColor Green
    } else {
        Write-Host "⚠️  NOTICE: Ensure 'config.yml' does not contain private live secrets before making repo public!" -ForegroundColor Yellow
    }
}

# 1. Create a detached orphan branch
$tempBranch = "temp-orphan-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
git checkout --orphan $tempBranch | Out-Null

# 2. Stage all current files
git add -A

# 3. Create the single clean commit
git commit -m "$CommitMessage"

# 4. Replace the target branch with the clean orphan branch
git branch -D $TargetBranch 2>$null
git branch -m $TargetBranch

# 5. Force-push to GitHub
Write-Host "🚀 Force-pushing single clean commit to $Remote/$TargetBranch..." -ForegroundColor Cyan
git push -f $Remote $TargetBranch

Write-Host ""
Write-Host "🎉 Clean push complete! Past git history has been completely purged on GitHub." -ForegroundColor Green
Write-Host "Only 1 single commit now exists on '$TargetBranch'." -ForegroundColor Green
