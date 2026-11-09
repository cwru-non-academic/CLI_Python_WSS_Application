# Trusted parent code only. This is local execution proof, not artifact authentication.
. "$PSScriptRoot/TrustedBaseline.ps1"
. "$PSScriptRoot/Read-OrdinaryPythonTooling.ps1"
. "$PSScriptRoot/SelectedProcessIsolation.ps1"
# Apply the existing source/index/input/origin boundary to the workflow authority,
# which can be distinct from the frozen runtime CLI fixture.
function Assert-PythonCliWorkflowSource([string]$Root) {
    Assert-BaselineRegularPath $Root
    $remote=(& git --no-optional-locks -C $Root remote get-url origin).Trim()
    if($LASTEXITCODE -ne 0 -or $remote -cnotmatch '^(https://github.com/|git@github.com:)cwru-non-academic/CLI_Python_WSS_Application(\.git)?$'){throw 'Wrong CLI workflow authority repository.'}
    if(@(& git --no-optional-locks -C $Root status --porcelain --untracked-files=all --ignored -- .github).Count -or $LASTEXITCODE -ne 0){throw 'Workflow authority cannot contain ignored or untracked executable inputs.'}
    if(@(& git --no-optional-locks -C $Root ls-files -v | Where-Object {$_ -cnotmatch '^H '}).Count -or $LASTEXITCODE -ne 0){throw 'Workflow authority cannot hide source changes in the Git index.'}
}
function Assert-PythonCliBaselineContent {
    param([string]$Root,[string]$PayloadRoot,[string]$WrapperRoot,[string]$WrapperSha,[string]$CliSha,
          [ValidateSet('committed','candidate')][string]$Mode,$Config,$Candidate,$Tooling=$null)
    # All validators were loaded from workflow-pinned tools BEFORE any selected code.
    $projection=Get-Content -LiteralPath (Join-Path $Root 'projection.json') -Raw | ConvertFrom-Json
    Assert-PythonSameCandidate $projection.candidate $Candidate
    Assert-PythonProjection $PayloadRoot $projection
    $schema=if($Mode -ceq 'candidate'){'wss-python-evidence/v1'}else{'wss-python-profile-evidence/v1'}
    foreach($stage in @('single','multi')) {
        $directory=if($stage -ceq 'single'){$Root}else{Join-Path $Root 'multi'}
        $e=Get-Content -LiteralPath (Join-Path $directory 'evidence.json') -Raw | ConvertFrom-Json
        if($e.schema -cne $schema -or $e.mode -cne $Mode -or $e.role -cne 'cli' -or
           $e.execution -cne 'pythonnet' -or $e.python_executed -cne $true -or
           $e.wrapper_sha -cne $WrapperSha -or $e.cli_sha -cne $CliSha -or
           $e.test_root -cne $WrapperRoot -or $e.test_sha -cne $WrapperSha -or
           $e.test_repository -cne 'cwru-non-academic/Python_WSS_Integration_Lib' -or
           $e.test_selection_id -or $e.test_contract_sha256 -or
           $e.stage -cne $stage -or $e.discovered -ne 16 -or $e.executed -ne 16 -or $e.passed -ne 16 -or
           $e.failed -ne 0 -or $e.skipped -ne 0 -or $e.assertion_expressions -ne 20 -or
           $e.sdk -cne $Config.dotnet_sdk -or $e.python -cne $Config.python_version -or
           $e.pythonnet -cne $Config.pythonnet_version -or $e.target_framework -cne 'net9.0' -or
           $e.test_framework -cne 'NUnit 3.14.0' -or
           $e.run_repository -cne $env:GITHUB_REPOSITORY -or [string]$e.run_id -cne [string]$env:GITHUB_RUN_ID -or
           $e.run_sha -cne $env:GITHUB_SHA -or $e.projection_sha256 -cne $projection.projection_sha256){
            throw 'Trusted CLI baseline source/runtime/mode/coverage binding mismatch.'
        }
        Assert-PythonSameCandidate $e.candidate $Candidate
        foreach($pair in @(@('results.xml','results_sha256'),@('dotnet.log','log_sha256'))){
            if((Get-FileHash -LiteralPath (Join-Path $directory $pair[0])).Hash.ToLowerInvariant() -cne $e.($pair[1])){throw 'Trusted CLI baseline content hash mismatch.'}
        }
        if($Mode -ceq 'candidate'){
            if($e.fixture_sha -cne $Config.fixture_commit -or $e.fixture_sha256 -cne $Config.fixture_sha256){throw 'Trusted CLI baseline fixture mismatch.'}
            Assert-PythonResults (Join-Path $directory 'results.xml') $Config -DotNet -Stage $stage
        }
    }
    $single=Get-Content -LiteralPath (Join-Path $Root 'evidence.json') -Raw | ConvertFrom-Json
    if($Mode -ceq 'candidate'){Assert-PythonMultiStageEvidence $Root $single $Config}
    else{
        $profile=Resolve-WssReviewedProfile $PayloadRoot $Candidate -SelectionEnabledCampaign
        if($profile.profile -cne 'layered-v1'){throw 'Modern selected CLI requires mandatory sixteen plus sixteen baseline.'}
        Assert-PythonProfileEvidence $Root $profile $projection $Tooling
    }
    # Native/platform gates remain independent mandatory workflow prerequisites.
    # Canonical local proof must never be advertised as native or campaign acceptance.
}
function Invoke-TrustedPythonCliBaseline {
    param([Parameter(Mandatory)][string]$ToolsRoot,[Parameter(Mandatory)][string]$WrapperRoot,
          [Parameter(Mandatory)][string]$WrapperSha,[Parameter(Mandatory)][string]$CliRoot,
          [Parameter(Mandatory)][string]$CliSha,[Parameter(Mandatory)][string]$OutputRoot,
          [Parameter(Mandatory)][ValidateSet('committed','candidate')][string]$Mode,
          [string]$FixtureRoot='', [string]$ArtifactRoot='', [string]$CandidatePath='', [string]$PythonExecutable='python',
          [string]$WorkflowSourceRoot, [string]$WorkflowSourceSha)
    $PythonExecutable=(Get-Command $PythonExecutable -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $hasRoot=$PSBoundParameters.ContainsKey('WorkflowSourceRoot')
    $hasSha=$PSBoundParameters.ContainsKey('WorkflowSourceSha')
    if(!$hasRoot -and !$hasSha){$WorkflowSourceRoot=$CliRoot;$WorkflowSourceSha=$CliSha}
    elseif(!$hasRoot -or !$hasSha -or [string]::IsNullOrWhiteSpace($WorkflowSourceRoot) -or [string]::IsNullOrWhiteSpace($WorkflowSourceSha)){throw 'Workflow source root and SHA must be supplied together and nonblank.'}
    # Trusted read-only Git checks must not refresh indexes captured by the parent.
    # Limit this to the helper read; do not change the child execution environment.
    $optionalLocks=[Environment]::GetEnvironmentVariable('GIT_OPTIONAL_LOCKS')
    try {
        $env:GIT_OPTIONAL_LOCKS='0'
        Assert-PythonCliWorkflowSource $WorkflowSourceRoot
        $toolsSha=Get-OrdinaryPythonToolsSha $WorkflowSourceRoot $WorkflowSourceSha
    } finally { [Environment]::SetEnvironmentVariable('GIT_OPTIONAL_LOCKS',$optionalLocks) }
    Assert-OrdinaryPythonToolsCheckout $ToolsRoot $toolsSha
    Assert-BaselineRegularPath $ToolsRoot
    $remote=(& git -C $ToolsRoot remote get-url origin).Trim()
    if($LASTEXITCODE -ne 0 -or $remote -cnotmatch '^(https://github.com/|git@github.com:)cwru-non-academic/Python_WSS_Integration_Lib(\.git)?$'){throw 'Wrong trusted tooling repository.'}
    if(@(& git -C $ToolsRoot status --porcelain --untracked-files=all --ignored -- .github).Count -or $LASTEXITCODE -ne 0){throw 'Tooling cannot contain ignored or untracked executable inputs.'}
    if(@(& git -C $ToolsRoot ls-files -v | Where-Object {$_ -cnotmatch '^H '}).Count -or $LASTEXITCODE -ne 0){throw 'Tooling cannot hide source changes in the Git index.'}
    $toolsBefore=New-TrustedBaselineSnapshot @($ToolsRoot)
    . (Join-Path $ToolsRoot '.github/scripts/PythonContract.ps1')
    . (Join-Path $ToolsRoot '.github/scripts/PythonProfiles/Contract.ps1')
    Assert-PythonSource $ToolsRoot $toolsSha
    Assert-PythonSource $WrapperRoot $WrapperSha
    Assert-PythonSource $CliRoot $CliSha -IgnoreSubmodule
    if(Test-Path -LiteralPath $OutputRoot){throw 'Trusted baseline output must be new; importing evidence is forbidden.'}
    $output=[IO.Path]::GetFullPath($OutputRoot)
    foreach($source in @($ToolsRoot,$WrapperRoot,$CliRoot,$WorkflowSourceRoot,$FixtureRoot,$ArtifactRoot) | Where-Object {$_}){
        $source=[IO.Path]::GetFullPath($source)
        if($output -eq $source -or $output.StartsWith($source+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $source.StartsWith($output+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Baseline output must not overlap any immutable source/input.'}
    }
    Assert-BaselineRegularPath ([IO.Path]::GetDirectoryName($output))
    $configPath=Join-Path $WrapperRoot '.github/python-ci.json'
    $config=Read-PythonConfig $configPath
    $options=@{WrapperRoot=$WrapperRoot;WrapperSha=$WrapperSha;CliRoot=$CliRoot;CliSha=$CliSha;
        ConfigPath=$configPath;OutputRoot=$OutputRoot;Mode=$Mode;Role='cli';Stage='all';PythonExe=$PythonExecutable}
    $toolBinding=$null
    if($Mode -ceq 'candidate'){
        if(!$FixtureRoot -or !$ArtifactRoot -or !$CandidatePath){throw 'Candidate baseline requires exact canonical fixture and authenticated resolver outputs.'}
        $candidate=Get-Content -LiteralPath $CandidatePath -Raw | ConvertFrom-Json
        Assert-PythonCandidate $candidate
        Assert-PythonSource $FixtureRoot $config.fixture_commit
        $options.FixtureRoot=$FixtureRoot;$options.ArtifactRoot=$ArtifactRoot;$options.CandidatePath=$CandidatePath
        $options.ToolsRoot=$ToolsRoot;$options.ToolsSha=$toolsSha;$options.ConfigPath=Join-Path $ToolsRoot '.github/python-ci.json'
        $runner=Join-Path $ToolsRoot '.github/scripts/Invoke-DotNetConformance.ps1'
        $payload=Join-Path $OutputRoot 'projection'
    }else{
        if($FixtureRoot -or $ArtifactRoot -or $CandidatePath){throw 'Committed mode cannot accept candidate inputs.'}
        Assert-PythonOrdinaryCliPair $CliRoot $CliSha $WrapperSha
        . (Join-Path $ToolsRoot '.github/scripts/PythonProfiles/Tooling.ps1')
        $options.ConfigPath=Join-Path $ToolsRoot '.github/python-ci.json'
        $options.ToolsRoot=$ToolsRoot;$options.ToolsSha=$toolsSha
        $toolBinding=Resolve-PythonOrdinaryTooling $ToolsRoot $toolsSha $options.ConfigPath $WrapperRoot $WrapperSha
        $config=$toolBinding.config;$candidate=$toolBinding.projection.candidate
        $payload=Join-Path $WrapperRoot 'Cs_Libraries'
        if($toolBinding.profile.profile -cne 'layered-v1'){throw 'Modern selected CLI is incompatible with legacy baseline; ordinary legacy coverage remains separate.'}
        $runner=Join-Path $ToolsRoot '.github/scripts/Invoke-ProfiledPythonConformance.ps1'
    }
    # All trusted identity/status reads precede this .git-inclusive snapshot.
    $authorityBefore=New-TrustedBaselineSnapshot @($WorkflowSourceRoot)
    # Baseline receives NO selected-root, selected-manifest, or selected-suite argument.
    $before=New-TrustedBaselineSnapshot @($ToolsRoot,(Join-Path $WrapperRoot 'conformance'),$configPath)
    Invoke-CredentialFreeSelectedPowerShell $runner $options
    Assert-TrustedBaselineSnapshot $before
    Assert-TrustedBaselineSnapshot $toolsBefore
    Assert-TrustedBaselineSnapshot $authorityBefore
    Assert-PythonCliBaselineContent $OutputRoot $payload $WrapperRoot $WrapperSha $CliSha $Mode $config $candidate $toolBinding
    [pscustomobject]@{payload_root=$payload;root=$OutputRoot;tools_sha=$toolsSha;workflow_source_sha=$WorkflowSourceSha}
}
