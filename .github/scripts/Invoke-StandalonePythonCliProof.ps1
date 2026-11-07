# Standalone candidate-source runtime proof. No Core inspect/evidence or activation.
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Workspace,[Parameter(Mandatory)][string]$VerifiedRoot,
      [Parameter(Mandatory)][string]$OutputRoot,[Parameter(Mandatory)][string]$ExpectedArchiveHash,
      [Parameter(Mandatory)][string]$ExpectedCandidateHash)
$ErrorActionPreference='Stop'
. "$PSScriptRoot/TrustedPythonCliBaseline.ps1"
$cliSha='76680d8c0698f1a028fa214d95bd8dc6d9098bc6'
$wrapperSha='9c375d7d39b7fe212483112effcdcdd5b61cf381'
$archiveHash='e6256d26b833f27f5b1ad11af4dfdcce03603020dc5c346b7c1e9b4b61ed927f'
$cli=Join-Path $Workspace 'cli';$wrapper=Join-Path $Workspace 'wrapper'
$tools=Join-Path $Workspace 'tools';$tests=Join-Path $Workspace 'selected-tests'
$fixture=Join-Path $Workspace 'fixture'
$archive=Join-Path $VerifiedRoot 'downloads/WSS-Universal-ci.zip'
$candidatePath=Join-Path $VerifiedRoot 'candidate.json'
Assert-BaselineRegularPath $VerifiedRoot
if($ExpectedArchiveHash -cne $archiveHash -or $ExpectedCandidateHash -cnotmatch '^[a-f0-9]{64}$' -or
   (Get-FileHash $archive).Hash.ToLowerInvariant() -cne $ExpectedArchiveHash -or
   (Get-FileHash $candidatePath).Hash.ToLowerInvariant() -cne $ExpectedCandidateHash){throw 'Verified input differs from direct trusted job outputs.'}
$candidate=Get-Content $candidatePath -Raw | ConvertFrom-Json
if($candidate.repository -cne 'cwru-non-academic/WSSCore' -or $candidate.commit -cne '0bc9e2d0af507ee729d39d3a30ab005cc136eabf' -or
   [string]$candidate.run_id -cne '42288988734' -or [string]$candidate.artifact_id -cne '13538204103' -or
   $candidate.archive -cne 'WSS-Universal-ci.zip' -or $candidate.sha256 -cne $archiveHash){throw 'Immutable candidate tuple mismatch.'}
$toolsSha=Get-OrdinaryPythonToolsSha $cli $cliSha
Assert-OrdinaryPythonToolsCheckout $tools $toolsSha
. "$tools/.github/scripts/PythonContract.ps1"
. "$tools/.github/scripts/wss-ci/Assert-UniversalArchive.ps1"
$contract=Get-PythonProducerContract $candidate.commit
$null=Get-WssUniversalArchiveHashes -Archive $archive -ExpectedSha256 $archiveHash -ExpectedFiles @(Get-WssUniversalFiles $contract)
if(Test-Path $OutputRoot){throw 'Standalone proof requires fresh output.'}
New-Item -ItemType Directory $OutputRoot | Out-Null
Expand-Archive -LiteralPath $archive -DestinationPath "$OutputRoot/input"
# Freeze parent code and verified producer inputs before any execution.
$authority=New-TrustedBaselineSnapshot @($PSScriptRoot,$VerifiedRoot)
$baseline=Invoke-TrustedPythonCliBaseline -ToolsRoot $tools -WrapperRoot $wrapper -WrapperSha $wrapperSha -CliRoot $cli -CliSha $cliSha -OutputRoot "$OutputRoot/baseline" -Mode candidate -FixtureRoot $fixture -ArtifactRoot "$OutputRoot/input/WSS-Universal" -CandidatePath $candidatePath
Assert-TrustedBaselineSnapshot $authority
$protected=New-TrustedBaselineSnapshot @($baseline.root,$baseline.payload_root,$tools,$cli,$wrapper)
$evidence="$OutputRoot/selected/test-source-evidence.json"
# Synthetic label only, deliberately not a Core selection identity.
$arguments=@('-B',"$PSScriptRoot/invoke_selected_cli_tests.py",'--product-root',$cli,'--product-sha',$cliSha,
    '--wrapper-root',$wrapper,'--wrapper-sha',$wrapperSha,'--payload-root',$baseline.payload_root,
    '--test-root',$tests,'--test-sha',$cliSha,'--test-repository','cwru-non-academic/CLI_Python_WSS_Application',
    '--test-selection-id',('a'*64),'--evidence',$evidence)
Invoke-CredentialFreeSelectedProcess (Get-Command python -CommandType Application).Source $arguments
Assert-TrustedBaselineSnapshot $authority
Assert-TrustedBaselineSnapshot $protected
$result=Get-Content $evidence -Raw | ConvertFrom-Json
if($result.tests_run -ne 10 -or $result.passed -cne $true){throw 'Required selected CLI10 did not pass.'}
@{schema='standalone-python-cli-proof/v1';scope='Windows candidate-source only; not Core campaign acceptance';baseline_single=16;baseline_multi=16;selected=10;parent_recheck=$true;cli=$cliSha;wrapper=$wrapperSha;tools=$toolsSha;candidate=$candidate} | ConvertTo-Json -Depth 8 | Set-Content "$OutputRoot/standalone-result.json"
