# tommyapi-quickstart for Windows: point Claude Code / Codex CLI at TommyAPI.
# https://github.com/Tommyapi/tommyapi-quickstart  (MIT)
# Plain text, auditable. Collects nothing. The only network call is one free
# GET /v1/models self-check at the end (skip with -NoCheck).
#
#   irm https://raw.githubusercontent.com/Tommyapi/tommyapi-quickstart/main/install.ps1 | iex
#     (reads $env:TOMMYAPI_KEY, $env:TOMMYAPI_ENDPOINT, $env:TOMMYAPI_TOOLS, $env:TOMMYAPI_MODEL)
#   & ([scriptblock]::Create((irm <url>))) -Key sk-xxx -Endpoint cn
param(
    [string]$Key = $env:TOMMYAPI_KEY,
    [string]$Endpoint = $(if ($env:TOMMYAPI_ENDPOINT) { $env:TOMMYAPI_ENDPOINT } else { 'us' }),
    [string]$Tools = $(if ($env:TOMMYAPI_TOOLS) { $env:TOMMYAPI_TOOLS } else { 'all' }),
    [string]$Model = $env:TOMMYAPI_MODEL,
    [switch]$DryRun,
    [switch]$Uninstall,
    [switch]$NoCheck,
    [switch]$NoUserEnv
)

$script:IsFile = [bool]$MyInvocation.MyCommand.Path
$script:Failed = $false

function Invoke-TommyApiInstall {
    $ErrorActionPreference = 'Stop'
    $homeDir = if ($env:TOMMYAPI_HOME) { $env:TOMMYAPI_HOME } else { $HOME }
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $utf8 = New-Object System.Text.UTF8Encoding($false)

    switch -Regex ($Endpoint) {
        '^us$' { $hostUrl = 'https://tommyapi.com'; break }
        '^cn$' { $hostUrl = 'https://cn.tommyapi.com'; break }
        '^sg$' { $hostUrl = 'https://sg.tommyapi.com'; break }
        '^https?://' { $hostUrl = $Endpoint.TrimEnd('/'); break }
        default { throw "-Endpoint must be us, cn or sg" }
    }

    $wantClaude = $false; $wantCodex = $false
    foreach ($t in ($Tools -split ',')) {
        switch ($t.Trim()) {
            'all' { $wantClaude = $true; $wantCodex = $true }
            'claude' { $wantClaude = $true }
            'claude-code' { $wantClaude = $true }
            'codex' { $wantCodex = $true }
            default { throw "unknown tool '$t' (supported: claude, codex, all; GUI clients are configured by hand, see README)" }
        }
    }

    $k = $Key
    if (-not $Uninstall) {
        if (-not $k) {
            if ($DryRun) { $k = 'sk-xxxxxxxx' }
            else {
                $sec = Read-Host 'TommyAPI key (sk-...)' -AsSecureString
                $k = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
            }
        }
        if ($k -notmatch '^[A-Za-z0-9._~+/=-]+$') { throw 'key is empty or contains unexpected characters' }
        if ($k -notlike 'sk-*') { Write-Host 'warning: key does not start with sk-' }
    }

    function Read-Text([string]$p) {
        if (Test-Path -LiteralPath $p) { return ([IO.File]::ReadAllText($p, $utf8) -replace "`r`n", "`n") }
        return $null
    }
    function Apply-File([string]$p, [string]$text) {
        $old = Read-Text $p
        if ($null -ne $old -and $old -ceq $text) { Write-Host "  = $p (unchanged)"; return }
        if ($DryRun) { Write-Host "  [dry-run] would write $p"; return }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $p) | Out-Null
        if ($null -ne $old) { Copy-Item -LiteralPath $p -Destination "$p.bak-tommyapi-$ts"; Write-Host "  backup: $p.bak-tommyapi-$ts" }
        [IO.File]::WriteAllText($p, $text, $utf8)
        Write-Host "  + $p"
    }
    function Remove-File([string]$p) {
        if (-not (Test-Path -LiteralPath $p)) { return }
        if ($DryRun) { Write-Host "  [dry-run] would remove $p (empty after uninstall)"; return }
        Copy-Item -LiteralPath $p -Destination "$p.bak-tommyapi-$ts"
        Remove-Item -LiteralPath $p -Force
        Write-Host "  - $p (empty after uninstall; backup: $p.bak-tommyapi-$ts)"
    }

    # ---- JSON (Claude Code settings.json) ----
    function Edit-Settings([string]$text, [string]$mode) {
        $obj = $null
        if ($text -and $text.Trim()) {
            try { $obj = $text | ConvertFrom-Json } catch { throw "settings.json is not valid JSON: $($_.Exception.Message)" }
            if ($obj -isnot [System.Management.Automation.PSCustomObject]) { throw 'settings.json is not a JSON object' }
        } else { $obj = New-Object PSObject }
        $env0 = $obj.PSObject.Properties['env']
        if ($mode -eq 'set') {
            if ($null -eq $env0 -or $env0.Value -isnot [System.Management.Automation.PSCustomObject]) { $e = New-Object PSObject } else { $e = $env0.Value }
            $e | Add-Member -NotePropertyName ANTHROPIC_BASE_URL -NotePropertyValue $hostUrl -Force
            $e | Add-Member -NotePropertyName ANTHROPIC_AUTH_TOKEN -NotePropertyValue $k -Force
            if ($Model) { $e | Add-Member -NotePropertyName ANTHROPIC_MODEL -NotePropertyValue $Model -Force }
            $obj | Add-Member -NotePropertyName env -NotePropertyValue $e -Force
        } elseif ($null -ne $env0 -and $env0.Value -is [System.Management.Automation.PSCustomObject]) {
            $e = $env0.Value
            $bu = $e.PSObject.Properties['ANTHROPIC_BASE_URL']
            if ($null -ne $bu -and "$($bu.Value)" -like '*tommyapi*') {
                foreach ($n in 'ANTHROPIC_BASE_URL', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_MODEL') { $e.PSObject.Properties.Remove($n) }
                if (@($e.PSObject.Properties).Count -eq 0) { $obj.PSObject.Properties.Remove('env') }
            }
        }
        return ((($obj | ConvertTo-Json -Depth 32) -replace "`r`n", "`n") + "`n")
    }

    # ---- TOML (Codex config.toml) ----
    function Strip-Toml([string]$text, [bool]$onlyOurs) {
        $out = New-Object System.Collections.Generic.List[string]
        $skipm = $false; $skipt = $false; $hdr = $false; $blank = 0; $started = $false
        foreach ($line in ($text -split "`n")) {
            $line = $line.TrimEnd("`r")
            if ($line -match '^# >>> tommyapi') { $skipm = $true; continue }
            if ($skipm) { if ($line -match '^# <<< tommyapi') { $skipm = $false }; continue }
            if ($line -match '^\s*\[\[?[A-Za-z0-9_."'' -]+\]\]?\s*(#.*)?$') {
                $hdr = $true
                $skipt = [bool]($line -match '^\s*\[model_providers\.tommyapi\]\s*(#.*)?$')
                if ($skipt) { continue }
            }
            if ($skipt) { continue }
            $keep = $false
            if ($onlyOurs -and $line -match '^# tommyapi-disabled: ') { $line = $line -replace '^# tommyapi-disabled: ', ''; $keep = $true }
            if (-not $keep -and -not $hdr -and $line -match '^\s*model_provider\s*=') {
                if ($onlyOurs -or $line -match 'tommyapi') { continue }
                $line = "# tommyapi-disabled: $line"
            }
            if ($line -match '^\s*$') { if ($started) { $blank++ }; continue }
            for ($i = 0; $i -lt $blank; $i++) { $out.Add('') }
            $blank = 0; $started = $true; $out.Add($line)
        }
        return ($out -join "`n")
    }

    $claudeFile = Join-Path $homeDir '.claude\settings.json'
    $codexFile = Join-Path $homeDir '.codex\config.toml'

    if ($Uninstall) { Write-Host 'Uninstalling TommyAPI entries (backups are kept)' } else { Write-Host "Configuring TommyAPI ($hostUrl)" }
    if ($DryRun) { Write-Host '(dry-run: nothing will be written)' }

    if ($wantClaude) {
        Write-Host "[claude] $claudeFile"
        $cur = Read-Text $claudeFile
        if ($Uninstall) {
            if ($null -eq $cur) { Write-Host '  (not present)' }
            else {
                $new = Edit-Settings $cur 'strip'
                if (($new -replace '\s', '') -eq '{}') { Remove-File $claudeFile } else { Apply-File $claudeFile $new }
            }
        } else {
            Apply-File $claudeFile (Edit-Settings $cur 'set')
        }
        if (-not $NoUserEnv -and -not $DryRun) {
            if ($Uninstall) {
                if ([Environment]::GetEnvironmentVariable('ANTHROPIC_BASE_URL', 'User') -like '*tommyapi*') {
                    foreach ($n in 'ANTHROPIC_BASE_URL', 'ANTHROPIC_AUTH_TOKEN', 'ANTHROPIC_MODEL') {
                        [Environment]::SetEnvironmentVariable($n, $null, 'User')
                    }
                    Write-Host '  - user environment variables ANTHROPIC_*'
                }
            } else {
                [Environment]::SetEnvironmentVariable('ANTHROPIC_BASE_URL', $hostUrl, 'User')
                [Environment]::SetEnvironmentVariable('ANTHROPIC_AUTH_TOKEN', $k, 'User')
                if ($Model) { [Environment]::SetEnvironmentVariable('ANTHROPIC_MODEL', $Model, 'User') }
                $env:ANTHROPIC_BASE_URL = $hostUrl; $env:ANTHROPIC_AUTH_TOKEN = $k
                Write-Host '  + user environment variables ANTHROPIC_BASE_URL / ANTHROPIC_AUTH_TOKEN'
            }
        }
    }

    if ($wantCodex) {
        Write-Host "[codex] $codexFile"
        $cur = Read-Text $codexFile
        if ($Uninstall) {
            if ($null -eq $cur) { Write-Host '  (not present)' }
            else {
                $rest = Strip-Toml $cur $true
                if (-not $rest) { Remove-File $codexFile } else { Apply-File $codexFile ($rest + "`n") }
            }
        } else {
            $rest = if ($null -ne $cur) { Strip-Toml $cur $false } else { '' }
            $t = "# >>> tommyapi >>>`nmodel_provider = `"tommyapi`"`n# <<< tommyapi <<<`n"
            if ($rest) { $t += "`n$rest`n" }
            $t += "`n# >>> tommyapi >>>`n[model_providers.tommyapi]`nname = `"TommyAPI`"`nbase_url = `"$hostUrl/v1`"`nenv_key = `"TOMMYAPI_KEY`"`nwire_api = `"responses`"`n# <<< tommyapi <<<`n"
            Apply-File $codexFile $t
        }
        if (-not $NoUserEnv -and -not $DryRun) {
            if ($Uninstall) {
                [Environment]::SetEnvironmentVariable('TOMMYAPI_KEY', $null, 'User')
                Write-Host '  - user environment variable TOMMYAPI_KEY'
            } else {
                [Environment]::SetEnvironmentVariable('TOMMYAPI_KEY', $k, 'User')
                $env:TOMMYAPI_KEY = $k
                Write-Host '  + user environment variable TOMMYAPI_KEY'
            }
        }
    }

    if (-not $Uninstall) {
        Write-Host ''
        Write-Host 'GUI clients (Cursor / Cline / Roo Code / Cherry Studio / Open WebUI): set'
        Write-Host "  Base URL = $hostUrl/v1   API Key = your key   (see README)"
        if (-not $NoCheck -and -not $DryRun) {
            try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}
            $code = 0
            try {
                $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 20 -Uri "$hostUrl/v1/models" -Headers @{ Authorization = "Bearer $k" }
                $code = [int]$r.StatusCode
            } catch {
                if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode } else { $code = 0 }
            }
            if ($code -eq 200) { Write-Host "Self-check: OK, $hostUrl/v1/models returned 200. Your key works." }
            elseif ($code -eq 401 -or $code -eq 403) { Write-Host "Self-check: HTTP $code, the key was rejected. Check it at https://tommyapi.com/console (Tokens page)." }
            elseif ($code -eq 0) { Write-Host 'Self-check: timed out / unreachable. Try -Endpoint cn (China) or -Endpoint sg (Singapore).' }
            else { Write-Host "Self-check: unexpected HTTP $code from $hostUrl/v1/models." }
        }
        Write-Host ''
        Write-Host 'Done. Open a NEW terminal, then run: claude   or   codex'
    } else { Write-Host 'Done.' }
}

$prevEap = $ErrorActionPreference
try { Invoke-TommyApiInstall }
catch {
    Write-Host "error: $($_.Exception.Message)" -ForegroundColor Red
    $script:Failed = $true
}
finally { $ErrorActionPreference = $prevEap }
# Never `exit` when run through `irm | iex`: it would close the user's terminal.
if ($script:Failed -and $script:IsFile) { exit 1 }
