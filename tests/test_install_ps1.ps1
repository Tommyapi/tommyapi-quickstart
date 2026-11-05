# Pure-PowerShell tests for install.ps1 (Windows PowerShell 5.1 and pwsh 7). Uses a fake home.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$script = Join-Path $root 'install.ps1'
$script:pass = 0; $script:fail = 0
$fake = 'sk-test-0123456789abcdef'
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Check([string]$d, [bool]$cond) {
    if ($cond) { $script:pass++; Write-Host "  ok   - $d" } else { $script:fail++; Write-Host "  FAIL - $d" }
}
function New-Home { $h = Join-Path ([IO.Path]::GetTempPath()) ("tq-" + [guid]::NewGuid().ToString('N')); New-Item -ItemType Directory $h | Out-Null; $env:TOMMYAPI_HOME = $h; return $h }
function Run([string[]]$a) {
    $h = @{ NoCheck = $true; NoUserEnv = $true }
    for ($i = 0; $i -lt $a.Count; $i++) {
        $n = $a[$i].TrimStart('-')
        if ($i + 1 -lt $a.Count -and $a[$i + 1] -notlike '-*') { $h[$n] = $a[$i + 1]; $i++ } else { $h[$n] = $true }
    }
    & $script @h *>&1 | Out-Null
}
function Raw([string]$p) { ([IO.File]::ReadAllText($p, $utf8) -replace "`r`n", "`n") }
function Baks([string]$p) { @(Get-ChildItem -Path "$p.bak-tommyapi-*" -ErrorAction SilentlyContinue).Count }
function Count-Lines([string]$p, [string]$pat) { @(Select-String -LiteralPath $p -Pattern $pat).Count }

Write-Host '== 1. fresh install'
$h = New-Home
Run @('-Key', $fake)
$s = Get-Content -Raw "$h\.claude\settings.json" | ConvertFrom-Json
Check 'settings base url (no /v1)' ($s.env.ANTHROPIC_BASE_URL -eq 'https://tommyapi.com')
Check 'settings token' ($s.env.ANTHROPIC_AUTH_TOKEN -eq $fake)
$t = Raw "$h\.codex\config.toml"
Check 'codex model_provider' ($t -match '(?m)^model_provider = "tommyapi"$')
Check 'codex provider table' ($t -match '(?m)^\[model_providers\.tommyapi\]$')
Check 'codex base_url /v1' ($t -match '(?m)^base_url = "https://tommyapi\.com/v1"$')
Check 'codex wire_api responses' ($t -match '(?m)^wire_api = "responses"$')
Check 'codex env_key' ($t -match '(?m)^env_key = "TOMMYAPI_KEY"$')
Check 'model_provider before first table' ($t.IndexOf('model_provider = ') -lt $t.IndexOf('['))
Check 'no backup for new files' ((Baks "$h\.claude\settings.json") -eq 0)

Write-Host '== 2. idempotent'
$b1 = (Raw "$h\.claude\settings.json") + (Raw "$h\.codex\config.toml")
Run @('-Key', $fake); Run @('-Key', $fake)
$b2 = (Raw "$h\.claude\settings.json") + (Raw "$h\.codex\config.toml")
Check 'content identical after 2 more runs' ($b1 -ceq $b2)
Check 'no new backups' (((Baks "$h\.claude\settings.json") + (Baks "$h\.codex\config.toml")) -eq 0)
Check 'single provider table' ((Count-Lines "$h\.codex\config.toml" '^\[model_providers\.tommyapi\]') -eq 1)

Write-Host '== 3. preserves existing config'
$h = New-Home
New-Item -ItemType Directory "$h\.claude", "$h\.codex" | Out-Null
$origS = "{`n  `"theme`": `"dark`",`n  `"permissions`": { `"allow`": [`"Bash(ls:*)`"] },`n  `"env`": { `"FOO`": `"bar`" }`n}`n"
$origT = "model = `"gpt-5`"`nmodel_provider = `"openai`"`n`n[mcp_servers.demo]`ncommand = `"demo`"`nargs = [`"a`", `"b`"]`n"
[IO.File]::WriteAllText("$h\.claude\settings.json", $origS, $utf8)
[IO.File]::WriteAllText("$h\.codex\config.toml", $origT, $utf8)
Run @('-Key', $fake, '-Endpoint', 'cn', '-Model', 'claude-sonnet-4-5')
$s = Get-Content -Raw "$h\.claude\settings.json" | ConvertFrom-Json
Check 'keeps theme' ($s.theme -eq 'dark')
Check 'keeps permissions' ($s.permissions.allow[0] -eq 'Bash(ls:*)')
Check 'keeps env.FOO' ($s.env.FOO -eq 'bar')
Check 'cn endpoint' ($s.env.ANTHROPIC_BASE_URL -eq 'https://cn.tommyapi.com')
Check 'model written' ($s.env.ANTHROPIC_MODEL -eq 'claude-sonnet-4-5')
$t = Raw "$h\.codex\config.toml"
Check 'toml keeps model' ($t -match '(?m)^model = "gpt-5"$')
Check 'toml keeps mcp table + args' (($t -match '(?m)^\[mcp_servers\.demo\]$') -and ($t -match '(?m)^args = \["a", "b"\]$'))
Check 'only one active model_provider' ((Count-Lines "$h\.codex\config.toml" '^model_provider') -eq 1)
Check 'settings backup exists' ((Baks "$h\.claude\settings.json") -eq 1)
Check 'toml backup exists' ((Baks "$h\.codex\config.toml") -eq 1)
Check 'backup holds original' ((Raw (Get-ChildItem "$h\.codex\config.toml.bak-tommyapi-*")[0].FullName) -ceq $origT)
Start-Sleep -Seconds 1
Run @('-Key', 'sk-test-NEWKEY', '-Endpoint', 'sg')
$s = Get-Content -Raw "$h\.claude\settings.json" | ConvertFrom-Json
Check 're-key updates token' ($s.env.ANTHROPIC_AUTH_TOKEN -eq 'sk-test-NEWKEY')
Check 're-key one table' ((Count-Lines "$h\.codex\config.toml" '^\[model_providers\.tommyapi\]') -eq 1)
Check 'sg base url' ((Raw "$h\.codex\config.toml") -match 'https://sg\.tommyapi\.com/v1')

Write-Host '== 4. -Uninstall restores'
Run @('-Uninstall')
$s = Get-Content -Raw "$h\.claude\settings.json" | ConvertFrom-Json
$o = $origS | ConvertFrom-Json
Check 'settings semantically original' ((($s | ConvertTo-Json -Depth 20 -Compress)) -ceq (($o | ConvertTo-Json -Depth 20 -Compress)))
Check 'config.toml identical to original' ((Raw "$h\.codex\config.toml") -ceq $origT)
Check 'backups kept' ((Baks "$h\.codex\config.toml") -ge 1)

Write-Host '== 5. uninstall removes files we created'
$h = New-Home
Run @('-Key', $fake); Run @('-Uninstall')
Check 'settings.json removed' (-not (Test-Path "$h\.claude\settings.json"))
Check 'config.toml removed' (-not (Test-Path "$h\.codex\config.toml"))

Write-Host '== 6. -DryRun writes nothing'
$h = New-Home
Run @('-Key', $fake, '-DryRun')
Check 'no files created' (-not (Test-Path "$h\.claude") -and -not (Test-Path "$h\.codex"))

Write-Host '== 7. -Tools filtering'
$h = New-Home
Run @('-Key', $fake, '-Tools', 'claude')
Check 'claude only' ((Test-Path "$h\.claude\settings.json") -and -not (Test-Path "$h\.codex\config.toml"))
$h = New-Home
Run @('-Key', $fake, '-Tools', 'codex')
Check 'codex only' ((Test-Path "$h\.codex\config.toml") -and -not (Test-Path "$h\.claude\settings.json"))

Write-Host '== 8. validation'
$h = New-Home
New-Item -ItemType Directory "$h\.claude" | Out-Null
[IO.File]::WriteAllText("$h\.claude\settings.json", '{ not json', $utf8)
Run @('-Key', $fake, '-Tools', 'claude')
Check 'invalid settings.json untouched' ((Raw "$h\.claude\settings.json") -ceq '{ not json')
$h = New-Home
Run @('-Key', 'sk-a"b')
Check 'bad key writes nothing' (-not (Test-Path "$h\.claude"))
Run @('-Key', $fake, '-Endpoint', 'mars')
Check 'bad endpoint writes nothing' (-not (Test-Path "$h\.claude"))

Write-Host '== 9. irm | iex form (reads env vars)'
$h = New-Home
$env:TOMMYAPI_KEY = $fake; $env:TOMMYAPI_ENDPOINT = 'sg'; $env:TOMMYAPI_TOOLS = 'claude'
$prevNoCheck = $null
# iex cannot pass switches; emulate by piping the script text, as `irm | iex` does
$src = [IO.File]::ReadAllText($script, $utf8)
$src = $src -replace '(?m)^\s*\[switch\]\$NoCheck,', '[switch]$NoCheck = $true,' -replace '(?m)^\s*\[switch\]\$NoUserEnv\s*$', '[switch]$NoUserEnv = $true'
$src | Invoke-Expression *>&1 | Out-Null
Remove-Item Env:TOMMYAPI_KEY, Env:TOMMYAPI_ENDPOINT, Env:TOMMYAPI_TOOLS
$s = Get-Content -Raw "$h\.claude\settings.json" | ConvertFrom-Json
Check 'iex: env key + sg endpoint honoured' (($s.env.ANTHROPIC_AUTH_TOKEN -eq $fake) -and ($s.env.ANTHROPIC_BASE_URL -eq 'https://sg.tommyapi.com'))
Check 'iex: tools=claude honoured' (-not (Test-Path "$h\.codex\config.toml"))

Write-Host '== 10. real self-check (free; 401 expected with fake key)'
$h = New-Home
$out = & $script -Key $fake -Tools claude -NoUserEnv *>&1 | Out-String
($out -split "`n" | Select-String 'Self-check') | ForEach-Object { Write-Host $_.Line }
Check 'self-check reports a verdict' ($out -match 'Self-check')

Write-Host ''
Write-Host "passed=$($script:pass) failed=$($script:fail)"
Remove-Item Env:TOMMYAPI_HOME -ErrorAction SilentlyContinue
if ($script:fail -gt 0) { exit 1 }
exit 0
