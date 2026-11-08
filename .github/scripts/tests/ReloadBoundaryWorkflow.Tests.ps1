# Source-only contract: no WSS payload is loaded or executed here.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$workflow = Get-Content (Join-Path $root '.github/workflows/cli-ci.yml') -Raw
$start = $workflow.IndexOf('      - name: Run additional interactive CLI reload boundaries')
if ($start -lt 0) { throw 'Missing additional reload workflow step.' }
$end = $workflow.IndexOf("`n      - ", $start + 1)
$body = if ($end -lt 0) { $workflow.Substring($start) } else { $workflow.Substring($start, $end - $start) }
$required = @(
    'Assert-OrdinaryPythonToolsCheckout $tools $toolSha',
    'Resolve-PythonOrdinaryTooling -ToolsRoot $tools -ToolsSha $toolSha',
    '-WrapperRoot $wrapper -WrapperSha $env:WRAPPER_SHA',
    "'legacy-v1' {", "'layered-v1' {",
    'this is not modern reload acceptance.',
    'default { throw ''Unknown reload capability profile.'' }',
    '$env:WSS_TEST_PAYLOAD = Join-Path $wrapper $PythonPluginPath',
    'python -B -m unittest discover -s cli/conformance -p test_command_reload_boundary.py -v',
    'if ($LASTEXITCODE -ne 0) { throw',
    '^Ran 4 tests in ', '^OK\s*$', 'skipped='
)
function Assert-ReloadStep([string]$Text) {
    foreach ($needle in $required) {
        if (!$Text.Contains($needle)) { throw "Missing reload invocation/profile guard: $needle" }
    }
    if ($Text -match 'continue-on-error:|(?m)^        if:') { throw 'Reload suite may not be bypassed by step conditions.' }
    if ($Text.IndexOf("'layered-v1' {") -ge $Text.IndexOf('python -B -m unittest discover')) { throw 'Runtime discovery must be inside the modern branch.' }
}
Assert-ReloadStep $body
$count = 1
foreach ($needle in $required) {
    $rejected = $false
    try { Assert-ReloadStep ($body.Replace($needle, 'REMOVED')) } catch { $rejected = $true }
    if (!$rejected) { throw "Mutation accepted: $needle" }
    $count++
}
foreach ($injection in @("`n        if: false", "`n        continue-on-error: true")) {
    $rejected = $false
    try { Assert-ReloadStep ($body + $injection) } catch { $rejected = $true }
    if (!$rejected) { throw 'Bypassed reload step accepted.' }
    $count++
}
Write-Output "PASS: $count reload workflow invocation, profile, count and bypass source contracts."