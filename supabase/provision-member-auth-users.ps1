param(
    [int]$Limit = 5,
    [switch]$All,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-RandomPassword {
    param([int]$Length = 20)

    $upper = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    $lower = 'abcdefghijkmnopqrstuvwxyz'
    $digits = '23456789'
    $symbols = '!@#$%*+-_?'

    $all = ($upper + $lower + $digits + $symbols).ToCharArray()
    $required = @(
        $upper[(Get-Random -Minimum 0 -Maximum $upper.Length)],
        $lower[(Get-Random -Minimum 0 -Maximum $lower.Length)],
        $digits[(Get-Random -Minimum 0 -Maximum $digits.Length)],
        $symbols[(Get-Random -Minimum 0 -Maximum $symbols.Length)]
    )

    $chars = New-Object System.Collections.Generic.List[char]
    foreach ($c in $required) { [void]$chars.Add($c) }

    for ($i = $chars.Count; $i -lt $Length; $i++) {
        [void]$chars.Add($all[(Get-Random -Minimum 0 -Maximum $all.Length)])
    }

    $shuffled = $chars | Sort-Object { Get-Random }
    return -join $shuffled
}

$repoRoot = Split-Path -Path $PSScriptRoot -Parent
Push-Location $repoRoot
try {
    $projectUrl = $env:CIDM_SUPABASE_URL
    if ([string]::IsNullOrWhiteSpace($projectUrl)) {
        $projectUrl = $env:SUPABASE_URL
    }

    if ([string]::IsNullOrWhiteSpace($projectUrl)) {
        throw 'Set CIDM_SUPABASE_URL or SUPABASE_URL before running this script. Example: https://<project-ref>.supabase.co'
    }

    $serviceRoleKey = $env:SUPABASE_SERVICE_ROLE_KEY
    if (-not $DryRun -and [string]::IsNullOrWhiteSpace($serviceRoleKey)) {
        throw 'SUPABASE_SERVICE_ROLE_KEY is required for create mode. Set it as an environment variable and rerun.'
    }

    if (-not $DryRun -and -not [string]::IsNullOrWhiteSpace($serviceRoleKey) -and $serviceRoleKey.StartsWith('sb_secret_')) {
        throw @'
This script calls the raw Auth Admin REST endpoint (/auth/v1/admin/users).
That endpoint requires the legacy JWT-based service_role key, not an sb_secret_ secret key.

Use the JWT service_role key from Supabase Dashboard > Project Settings > API, then rerun:

$env:SUPABASE_URL="https://<project-ref>.supabase.co"
$env:SUPABASE_SERVICE_ROLE_KEY="<service_role JWT>"
./supabase/provision-member-auth-users.ps1 -Limit 5
'@
    }

    $limitSql = if ($All) { '' } else { "limit $Limit" }
        $candidateSql = @"
select
  m.id,
    lower(btrim(m.login_id)) as login_id
from public.member m
left join auth.users u
  on lower(btrim(coalesce(u.email, ''))) = lower(btrim(coalesce(m.login_id, '')))
where m.auth_user_id is null
  and nullif(btrim(coalesce(m.login_id, '')), '') is not null
  and u.id is null
order by lower(btrim(m.login_id))
$limitSql
"@

    $rawCandidates = supabase db query --linked --output json $candidateSql | Out-String
    $parsed = $rawCandidates | ConvertFrom-Json

    $candidates = @()
    if ($parsed -is [System.Array]) {
        $candidates = $parsed
    } elseif ($parsed.rows) {
        $candidates = $parsed.rows
    } elseif ($parsed.data) {
        $candidates = $parsed.data
    }

    if (-not $candidates -or $candidates.Count -eq 0) {
        Write-Host 'No candidates to provision. member.auth_user_id is already linked or auth.users already has these emails.'
        exit 0
    }

    Write-Host "Candidates: $($candidates.Count)"
    $candidates | Select-Object id, login_id | Format-Table -AutoSize

    if ($DryRun) {
        Write-Host 'DryRun enabled. No users were created.'
        exit 0
    }

    $headers = @{
        'apikey'        = $serviceRoleKey
        'Authorization' = "Bearer $serviceRoleKey"
        'Content-Type'  = 'application/json'
    }

    $createdEmails = New-Object System.Collections.Generic.List[string]
    $failed = New-Object System.Collections.Generic.List[string]

    foreach ($candidate in $candidates) {
        $email = [string]$candidate.login_id
        $password = New-RandomPassword
        $body = @{
            email         = $email
            password      = $password
            email_confirm = $true
            user_metadata = @{
                member_id    = [string]$candidate.id
            }
            app_metadata  = @{
                app_role = 'member'
            }
        } | ConvertTo-Json -Depth 6

        try {
            [void](Invoke-RestMethod -Method Post -Uri "$projectUrl/auth/v1/admin/users" -Headers $headers -Body $body)
            [void]$createdEmails.Add($email)
            Write-Host "Created auth user: $email"
        } catch {
            $failedMessage = "$email :: $($_.Exception.Message)"
            [void]$failed.Add($failedMessage)
            Write-Warning $failedMessage
        }
    }

    $linkSql = @"
update public.member m
set auth_user_id = u.id,
    auth_linked_at = coalesce(m.auth_linked_at, now())
from auth.users u
where m.auth_user_id is null
  and nullif(btrim(coalesce(m.login_id, '')), '') is not null
  and lower(btrim(coalesce(m.login_id, ''))) = lower(btrim(coalesce(u.email, '')));
"@

    supabase db query --linked --output table $linkSql | Out-Host

    Write-Host ''
    Write-Host "Created users : $($createdEmails.Count)"
    Write-Host "Failed users  : $($failed.Count)"
    if ($failed.Count -gt 0) {
        Write-Host 'Failed details:'
        $failed | ForEach-Object { Write-Host " - $_" }
    }

    $summarySql = @"
select
  count(*) as total_members,
  count(auth_user_id) as linked_members,
  count(*) - count(auth_user_id) as unlinked_members
from public.member;
"@
    supabase db query --linked --output table $summarySql | Out-Host
} finally {
    Pop-Location
}
