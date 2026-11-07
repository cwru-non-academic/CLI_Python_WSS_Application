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

# Exact path identity is ordinal, independent of culture and Unicode normalization.
$ordinalBase=Join-Path ((& python -c 'import os,tempfile; print(os.path.realpath(tempfile.gettempdir()))').Trim()) ('ordinal-inventory-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $ordinalBase
foreach($name in @('Z.txt','a.txt')){[IO.File]::WriteAllText((Join-Path $ordinalBase $name),'same')}
$ordinalSnapshot=New-TrustedBaselineSnapshot @($ordinalBase)
Assert-TrustedBaselineSnapshot $ordinalSnapshot
$expected=[string[]]$ordinalSnapshot.inventory.Clone()
[Array]::Sort($expected,[StringComparer]::Ordinal)
for($i=0;$i -lt $expected.Count;$i++){if(![StringComparer]::Ordinal.Equals($expected[$i],$ordinalSnapshot.inventory[$i])){throw 'Inventory ordering is not ordinal.'}}
if($IsLinux){
    [IO.File]::WriteAllText((Join-Path $ordinalBase 'Case.txt'),'same')
    $before=New-TrustedBaselineSnapshot @($ordinalBase)
    [IO.File]::WriteAllText((Join-Path $ordinalBase 'case.txt'),'same')
    $rejected=$false;try{Assert-TrustedBaselineSnapshot $before}catch{$rejected=$true}
    if(!$rejected){throw 'Accepted case-distinct path addition.'}
    Write-Output 'PASS: Linux case-distinct path addition rejected.'
}
if(!$IsMacOS){
    # Linux/NTFS preserve these distinct spellings; macOS commonly normalizes names.
    $unicodeRoot=Join-Path $ordinalBase 'unicode'
    $null=New-Item -ItemType Directory -Path $unicodeRoot
    $composed=([string][char]0x00e9)+'.txt'
    $decomposed='e'+([string][char]0x0301)+'.txt'
    [IO.File]::WriteAllText((Join-Path $unicodeRoot $composed),'same')
    $before=New-TrustedBaselineSnapshot @($unicodeRoot)
    Move-Item -LiteralPath (Join-Path $unicodeRoot $composed) -Destination (Join-Path $unicodeRoot $decomposed)
    $rejected=$false;try{Assert-TrustedBaselineSnapshot $before}catch{$rejected=$true}
    if(!$rejected){throw 'Accepted normalization-equivalent path rename.'}
    Write-Output 'PASS: Unicode normalization-equivalent path rename rejected.'
}
Write-Output 'PASS: exact ordinal inventory ordering and identity.'
