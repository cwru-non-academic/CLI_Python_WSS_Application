# Read the expected immutable parent pin from the exact ordinary workflow source.
function Get-OrdinaryPythonToolsSha([string]$ApplicationRoot,[string]$ApplicationSha) {
    if($ApplicationSha -cnotmatch '^[a-f0-9]{40}$'){throw 'Exact application source SHA required.'}
    $head=(& git -C $ApplicationRoot rev-parse HEAD).Trim()
    if($LASTEXITCODE -ne 0 -or $head -cne $ApplicationSha){throw 'Application checkout differs from workflow source.'}
    $dirty=& git -C $ApplicationRoot status --porcelain --untracked-files=all --ignore-submodules=all
    if($LASTEXITCODE -ne 0 -or $dirty){throw 'Application workflow source must remain clean.'}
    $text=(& git -C $ApplicationRoot show "${ApplicationSha}:.github/workflows/cli-ci.yml") -join "`n"
    if($LASTEXITCODE -ne 0){throw 'Cannot read committed ordinary workflow.'}
    $pattern='(?m)^\s*repository: cwru-non-academic/Python_WSS_Integration_Lib\s*\r?\n\s*ref: ([^\r\n]+?)\s*\r?\n\s*path: tools\s*$'
    $pins=@([regex]::Matches($text,$pattern) | ForEach-Object {$_.Groups[1].Value} | Sort-Object -Unique)
    if($pins.Count -ne 1 -or $pins[0] -cnotmatch '^[a-f0-9]{40}$'){throw 'Ordinary workflow must declare one consistent immutable Python tooling source.'}
    $pins[0]
}
function Assert-OrdinaryPythonToolsCheckout([string]$ToolsRoot,[string]$ExpectedSha) {
    if($ExpectedSha -cnotmatch '^[a-f0-9]{40}$' -or (& git -C $ToolsRoot rev-parse HEAD).Trim() -cne $ExpectedSha -or $LASTEXITCODE -ne 0){throw 'Tools checkout differs from the committed workflow pin.'}
    $dirty=& git -C $ToolsRoot status --porcelain --untracked-files=all
    if($LASTEXITCODE -ne 0 -or $dirty){throw 'Tools checkout must remain clean.'}
}
