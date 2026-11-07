$ErrorActionPreference='Stop'
. "$PSScriptRoot/../Read-OrdinaryPythonTooling.ps1"
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$temp=Join-Path ([IO.Path]::GetTempPath()) ('cli-tools-pin-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path (Join-Path $temp '.github/workflows') -Force
$workflow=Join-Path $temp '.github/workflows/cli-ci.yml'
$original=Get-Content (Join-Path $root '.github/workflows/cli-ci.yml') -Raw
function Commit-Workflow([string]$Text){[IO.File]::WriteAllText($workflow,$Text);git -C $temp add . | Out-Null;git -C $temp -c user.name=Fixture -c user.email=fixture@example.invalid commit -q -m Fixture;if($LASTEXITCODE){throw 'Fixture failed'};(git -C $temp rev-parse HEAD).Trim()}
git -C $temp init -q
$sha=Commit-Workflow $original
$expected=Get-OrdinaryPythonToolsSha $temp $sha
if($expected -cnotmatch '^[a-f0-9]{40}$'){throw 'Exact workflow source pin missing.'}
$count=1
function Reject([scriptblock]$Action){try{& $Action | Out-Null}catch{$script:count++;return};throw 'Unsafe ordinary tooling pin accepted.'}
Reject {Get-OrdinaryPythonToolsSha $temp ('f'*40)}
Reject {Assert-OrdinaryPythonToolsCheckout $temp ('f'*40)}
Add-Content $workflow ' '
Reject {Get-OrdinaryPythonToolsSha $temp $sha}
$sha=Commit-Workflow ($original.Replace("ref: $expected",'ref: main'))
Reject {Get-OrdinaryPythonToolsSha $temp $sha}
$changed=[regex]::new([regex]::Escape("ref: $expected")).Replace($original,('ref: '+('f'*40)),1)
$sha=Commit-Workflow $changed
Reject {Get-OrdinaryPythonToolsSha $temp $sha}
Write-Output "PASS: $count committed source, immutable tooling, dirty source, mutable and divergent pin checks."
