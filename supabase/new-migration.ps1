param(
    [Parameter(Mandatory = $true)]
    [string]$Name,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Convert free-form migration names to snake_case and remove invalid characters.
$slug = $Name.ToLowerInvariant().Trim()
$slug = [regex]::Replace($slug, '[^a-z0-9]+', '_')
$slug = [regex]::Replace($slug, '^_+|_+$', '')

if ([string]::IsNullOrWhiteSpace($slug)) {
    throw 'Migration name is empty after normalization. Use letters/numbers (example: harden_admin_policy).'
}

$timestamp = Get-Date -Format 'yyyyMMddHHmmss'
$migrationName = "${timestamp}_${slug}"

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
$command = "npx supabase migration new $migrationName"

Write-Host "Repository : $repoRoot"
Write-Host "Migration  : $migrationName"
Write-Host "Command    : $command"

if ($DryRun) {
    Write-Host 'DryRun enabled. Command was not executed.'
    exit 0
}

Push-Location $repoRoot
try {
    Invoke-Expression $command
} finally {
    Pop-Location
}

Write-Host ''
Write-Host 'Created migration file in supabase/migrations. Next steps:'
Write-Host '1) Edit SQL'
Write-Host '2) npx supabase db push --linked --dry-run --yes'
Write-Host '3) npx supabase db push --linked --yes'
