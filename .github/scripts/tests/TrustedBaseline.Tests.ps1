$ErrorActionPreference='Stop'
. "$PSScriptRoot/../TrustedBaseline.ps1"
. "$PSScriptRoot/../SelectedProcessIsolation.ps1"
$temp=(& python -c 'import os,tempfile; print(os.path.realpath(tempfile.gettempdir()))').Trim()
if($LASTEXITCODE -ne 0){throw 'Cannot resolve physical temporary directory.'}
$base=Join-Path $temp ('cli-baseline-snapshot-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $base
$child=Join-Path $base 'child.ps1'
@'
param([string]$Root,[string]$Action)
$ErrorActionPreference='Stop'
switch($Action){
 'none' {}
 'modify' {[IO.File]::WriteAllText((Join-Path $Root 'baseline/evidence.json'),'changed')}
 'add-file' {[IO.File]::WriteAllText((Join-Path $Root 'baseline/extra.json'),'extra')}
 'delete-file' {Remove-Item -LiteralPath (Join-Path $Root 'baseline/evidence.json')}
 'add-dir' {$null=New-Item -ItemType Directory -Path (Join-Path $Root 'baseline/extra')}
 'delete-dir' {Remove-Item -LiteralPath (Join-Path $Root 'baseline/empty')}
 'core' {[IO.File]::WriteAllText((Join-Path $Root 'core/tools/selection.mjs'),'changed')}
 'core-add' {[IO.File]::WriteAllText((Join-Path $Root 'core/package.json'),'{}')}
 'lock' {[IO.File]::WriteAllText((Join-Path $Root 'caller/wss-ci.lock.json'),'changed')}
 'context' {[IO.File]::WriteAllText((Join-Path $Root 'context.json'),'changed')}
 'roots' {[IO.File]::WriteAllText((Join-Path $Root 'roots.json'),'changed')}
 'redirect' {
   Move-Item -LiteralPath (Join-Path $Root 'baseline') -Destination (Join-Path $Root 'redirected')
   $type=if($IsWindows){'Junction'}else{'SymbolicLink'}
   $null=New-Item -ItemType $type -Path (Join-Path $Root 'baseline') -Target (Join-Path $Root 'redirected')
 }
 'ancestor' {
   Move-Item -LiteralPath (Join-Path $Root 'core') -Destination (Join-Path $Root 'redirected-core')
   $type=if($IsWindows){'Junction'}else{'SymbolicLink'}
   $null=New-Item -ItemType $type -Path (Join-Path $Root 'core') -Target (Join-Path $Root 'redirected-core')
 }
 default {throw 'Unknown action.'}
}
'@ | Set-Content -LiteralPath $child
foreach($action in @('none','modify','add-file','delete-file','add-dir','delete-dir','redirect','ancestor','core','core-add','lock','context','roots')){
    $root=Join-Path $base $action
    foreach($directory in @('baseline/empty','core/tools','caller')){$null=New-Item -ItemType Directory -Path (Join-Path $root $directory) -Force}
    foreach($file in @('baseline/evidence.json','core/tools/selection.mjs','caller/wss-ci.lock.json','context.json','roots.json')){[IO.File]::WriteAllText((Join-Path $root $file),'original')}
    $snapshot=New-TrustedBaselineSnapshot @((Join-Path $root 'baseline'),(Join-Path $root 'core'),(Join-Path $root 'caller'),(Join-Path $root 'context.json'),(Join-Path $root 'roots.json'))
    Invoke-CredentialFreeSelectedPowerShell $child @{Root=$root;Action=$action}
    $rejected=$false
    try{Assert-TrustedBaselineSnapshot $snapshot}catch{$rejected=$true}
    if(($action -ceq 'none' -and $rejected) -or ($action -cne 'none' -and !$rejected)){throw "Snapshot regression: $action"}
    Write-Host "PASS: actual child $action"
}
# Keep disposable fixtures for diagnosis; no source or global paths are removed.
Write-Host "PASS: baseline/authority snapshots; fixtures $base"
